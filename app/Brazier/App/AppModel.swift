import Foundation
import Observation
import SwiftUI

enum BayState: Equatable {
    case blank
    case warming
    case mounted
    case faulted(String)
}

struct ProbeResult: Equatable {
    var health: Signal = .none
    var healthWord = "NOT PROBED"
    var user: Signal = .none
    var userWord = "NOT PROBED"
}

/// The root store: servers, the mounted server's readings, the fault rail, push.
/// Nothing here is optimistic. A reading changes only after the server answered.
@MainActor
@Observable
final class AppModel {
    let store = ServerStore()
    let credentials = CredentialProvider()
    let push = PushManager()

    var selectedServerID: UUID? {
        didSet { UserDefaults.standard.set(selectedServerID?.uuidString, forKey: "selectedServer") }
    }
    private(set) var alerts: [GrafanaAlert] = []
    private(set) var silences: [Silence] = []
    /// The mounted server's organizations, as /api/user/orgs listed them. One means no chips, no switcher.
    private(set) var orgs: [GrafanaOrg] = []
    private(set) var asOf: Date?
    private(set) var lastFailure: Date?
    private(set) var bay: BayState = .blank
    private(set) var faults: [Fault] = []
    private(set) var signedIn = false
    private(set) var accountName: String?
    var pendingAlert: GrafanaAlert?
    private var refreshing = false
    private var refreshAgain = false
    private var accountNames: [UUID: String] = [:]
    private var orgCache: [UUID: [GrafanaOrg]] = [:]
    private var orgSelections: [UUID: OrgSelection] = [:]
    private var prefsSync: Task<Void, Never>?

    init() {
        if let raw = UserDefaults.standard.string(forKey: "selectedServer"),
           let id = UUID(uuidString: raw), store.server(id: id) != nil {
            selectedServerID = id
        } else {
            selectedServerID = store.servers.first?.id
        }
        bay = store.servers.isEmpty ? .blank : .warming
        #if DEBUG
        seedFromEnvironment()
        #endif
    }

    #if DEBUG
    /// Development only: `simctl launch` with SIMCTL_CHILD_BRAZIER_SEED_URL / _TOKEN / _NAME mounts a
    /// token-mode server without touching the UI, so a headless build host can screenshot real readings.
    /// _USER and _PASSWORD instead of _TOKEN sign in through Grafana's JSON login endpoint for a session
    /// server, the only kind that can belong to several organizations.
    private func seedFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["BRAZIER_SEED_URL"], let url = URL(string: raw) else { return }
        let token = env["BRAZIER_SEED_TOKEN"]
        let password = env["BRAZIER_SEED_PASSWORD"]
        guard token != nil || password != nil else { return }
        let mode: Server.AuthMode = token != nil ? .token : .session
        let server: Server
        if let existing = store.servers.first(where: { $0.url == url && $0.auth == mode }) {
            server = existing
        } else {
            server = Server(name: env["BRAZIER_SEED_NAME"] ?? (url.host ?? "Seeded"), url: url, auth: mode)
            store.add(server)
        }
        selectedServerID = server.id
        bay = .warming
        if let org = env["BRAZIER_SHOT_ORG"], Int(org) != nil {
            UserDefaults.standard.set(org, forKey: "orgSelection.\(server.id.uuidString)")
        }
        if let token {
            do { try Keychain.set(token, for: SecretKey.apiToken(server.id)) }
            catch { record("keychain seed", error) }
        } else if let password, let user = env["BRAZIER_SEED_USER"] {
            Task {
                do {
                    let result = try await ServerProbe.passwordSignIn(url, user: user, password: password)
                    try await credentials.storeSession(cookie: result.cookieHeader, expiry: result.expiry, for: server)
                    accountNames[server.id] = result.user.login
                    await refresh()
                } catch {
                    record("seed sign-in", error)
                }
            }
        }
    }
    #endif

    var selectedServer: Server? { store.server(id: selectedServerID) }

    func client(for server: Server) -> GrafanaClient {
        GrafanaClient(server: server, credentials: credentials)
    }

    // MARK: Organizations

    /// Which organizations the tabs read on the mounted server. Kept per server, across launches.
    var orgSelection: OrgSelection {
        get {
            guard let id = selectedServerID else { return .all }
            if let kept = orgSelections[id] { return kept }
            return OrgSelection(stored: UserDefaults.standard.string(forKey: "orgSelection.\(id.uuidString)"))
        }
        set {
            guard let id = selectedServerID, newValue != orgSelection else { return }
            orgSelections[id] = newValue
            UserDefaults.standard.set(newValue.stored, forKey: "orgSelection.\(id.uuidString)")
            Task { await refresh() }
        }
    }

    /// The organizations the selection resolves to; a selection the server no longer has reads as all.
    var selectedOrgs: [GrafanaOrg] {
        if case .one(let id) = orgSelection {
            let one = orgs.filter { $0.orgId == id }
            if !one.isEmpty { return one }
        }
        return orgs
    }

    var hasSeveralOrgs: Bool { orgs.count > 1 }

    /// Rows say which organization they came from only when more than one is on the screen.
    var showsOrgChips: Bool { selectedOrgs.count > 1 }

    var orgSelectionWord: String {
        if case .one(let id) = orgSelection, let org = orgs.first(where: { $0.orgId == id }) { return org.name }
        return "All organizations"
    }

    // MARK: Mounting and reading

    func select(_ server: Server) {
        selectedServerID = server.id
        alerts = []
        silences = []
        orgs = orgCache[server.id] ?? []
        asOf = nil
        lastFailure = nil
        bay = .warming
        Task { await refresh() }
    }

    func refresh() async {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        repeat {
            refreshAgain = false
            await read()
        } while refreshAgain
        refreshing = false
    }

    private func read() async {
        guard let server = selectedServer else {
            bay = .blank
            return
        }
        signedIn = await credentials.isSignedIn(server)
        accountName = await credentials.subjectName(server) ?? accountNames[server.id]
        guard signedIn else {
            bay = .faulted("Not signed in")
            return
        }
        do {
            let client = client(for: server)
            if accountName == nil, let user = try? await client.user() {
                accountName = user.login
                accountNames[server.id] = user.login
            }
            // A Grafana that refuses the list (an old one, a gate in front) is read as one organization.
            if orgCache[server.id] == nil, let list = try? await client.orgs() {
                orgCache[server.id] = list
            }
            orgs = orgCache[server.id] ?? []
            let targets = selectedOrgs
            if targets.isEmpty {
                async let alertsRead = client.alerts()
                async let silencesRead = client.silences()
                alerts = try await alertsRead
                silences = (try? await silencesRead) ?? []
            } else {
                let reading = await Self.read(client, orgs: targets)
                if reading.failures.count == targets.count, let first = reading.failures.first {
                    throw first.error
                }
                if let ended = reading.failures.first(where: { $0.error is AuthError }) {
                    throw ended.error
                }
                for failure in reading.failures {
                    record("GET /api/prometheus/grafana/api/v1/alerts · \(failure.org.name)", failure.error)
                }
                alerts = reading.alerts
                silences = reading.silences
            }
            asOf = Date()
            bay = .mounted
        } catch let error as AuthError {
            signedIn = false
            alerts = []
            bay = .faulted(error.localizedDescription)
        } catch {
            lastFailure = Date()
            record("GET /api/prometheus/grafana/api/v1/alerts", error)
            if alerts.isEmpty { bay = .faulted(error.localizedDescription) }
        }
    }

    private struct OrgReading {
        var alerts: [GrafanaAlert] = []
        var silences: [Silence] = []
        var failures: [(org: GrafanaOrg, error: Error)] = []
    }

    /// Every organization at once; each answer is tagged with the organization it came from.
    private static func read(_ client: GrafanaClient, orgs: [GrafanaOrg]) async -> OrgReading {
        await withTaskGroup(of: (GrafanaOrg, Result<([GrafanaAlert], [Silence]), Error>).self) { group in
            for org in orgs {
                group.addTask {
                    do {
                        async let alerts = client.alerts(org: org.orgId)
                        async let silences = client.silences(org: org.orgId)
                        let read = try await alerts.map { $0.tagged(org) }
                        let quiet = ((try? await silences) ?? []).map { $0.tagged(org) }
                        return (org, .success((read, quiet)))
                    } catch {
                        return (org, .failure(error))
                    }
                }
            }
            var reading = OrgReading()
            var byOrg: [Int: ([GrafanaAlert], [Silence])] = [:]
            for await (org, result) in group {
                switch result {
                case .success(let pair): byOrg[org.orgId] = pair
                case .failure(let error): reading.failures.append((org, error))
                }
            }
            for org in orgs {
                guard let pair = byOrg[org.orgId] else { continue }
                reading.alerts += pair.0
                reading.silences += pair.1
            }
            return reading
        }
    }

    // MARK: Servers

    /// Adds a server with whatever secret the walkthrough verified for it.
    func add(_ server: Server, apiToken: String? = nil, session: (cookie: String, expiry: String?)? = nil, tokens: TokenResponse? = nil, login: String? = nil) async {
        store.add(server)
        do {
            if let apiToken, !apiToken.isEmpty { try await credentials.storeAPIToken(apiToken, for: server) }
            if let session { try await credentials.storeSession(cookie: session.cookie, expiry: session.expiry, for: server) }
            if let tokens { try await credentials.store(tokens, for: server) }
        } catch {
            record("keychain \(server.host)", error)
        }
        if let login { accountNames[server.id] = login }
        if selectedServerID == nil { select(server) }
    }

    func remove(_ server: Server) async {
        await deregisterPush(using: server)
        store.remove(server)
        accountNames[server.id] = nil
        orgCache[server.id] = nil
        orgSelections[server.id] = nil
        UserDefaults.standard.removeObject(forKey: "orgSelection.\(server.id.uuidString)")
        UserDefaults.standard.removeObject(forKey: "notificationPrefs.\(server.id.uuidString)")
        if selectedServerID == server.id {
            selectedServerID = store.servers.first?.id
            if let next = selectedServer { select(next) } else { alerts = []; bay = .blank }
        }
    }

    func probe(_ server: Server) async -> ProbeResult {
        var result = ProbeResult()
        let client = client(for: server)
        do {
            let health = try await client.health()
            result.health = health.database == "ok" ? .ok : .wait
            result.healthWord = "GRAFANA \(health.version)"
        } catch {
            result.health = .stop
            result.healthWord = error.localizedDescription
            return result
        }
        if await credentials.isSignedIn(server) {
            do {
                let user = try await client.user()
                result.user = .ok
                result.userWord = user.login
            } catch {
                result.user = .stop
                result.userWord = error.localizedDescription
            }
        } else {
            result.userWord = "NOT SIGNED IN"
        }
        return result
    }

    // MARK: Sign-in

    /// Single sign-on through the provider. Session servers sign in through the web view instead.
    func signIn(_ server: Server) async -> ThrowResult {
        guard case .oidc(let issuer, let clientID) = server.auth else {
            return .refuse("This server does not sign in through a provider")
        }
        do {
            let tokens = try await OIDC.signIn(issuer: issuer, clientID: clientID)
            try await credentials.store(tokens, for: server)
            let who = await credentials.subjectName(server) ?? "you"
            if selectedServerID == server.id || selectedServerID == nil { select(server) }
            await registerPush()
            return .pass("Signed in as \(who)")
        } catch OIDCError.cancelled {
            return .refuse("Sign-in cancelled")
        } catch {
            record("OIDC sign-in \(server.host)", error)
            return .refuse(error.localizedDescription)
        }
    }

    /// The web view finished Grafana's own sign-in: keep the session and read again.
    func completeSessionSignIn(_ server: Server, cookie: String, expiry: String?, user: GrafanaUser) async -> ThrowResult {
        do {
            try await credentials.storeSession(cookie: cookie, expiry: expiry, for: server)
            accountNames[server.id] = user.login
            if selectedServerID == server.id || selectedServerID == nil { select(server) }
            await registerPush()
            return .pass("Signed in as \(user.login)")
        } catch {
            record("keychain \(server.host)", error)
            return .refuse(error.localizedDescription)
        }
    }

    func signOut(_ server: Server) async {
        await deregisterPush(using: server)
        await credentials.forget(server)
        accountNames[server.id] = nil
        if selectedServerID == server.id {
            alerts = []
            silences = []
            signedIn = false
            accountName = nil
            bay = .faulted("Not signed in")
        }
    }

    func saveToken(_ token: String, for server: Server) async -> ThrowResult {
        do {
            try await credentials.storeAPIToken(token, for: server)
            if selectedServerID == server.id { select(server) }
            return .pass("Token stored for \(server.name)")
        } catch {
            record("keychain \(server.host)", error)
            return .refuse(error.localizedDescription)
        }
    }

    // MARK: Silences

    func silence(alert: GrafanaAlert, duration: SilenceDuration, comment: String, on server: Server? = nil) async -> ThrowResult {
        guard let server = server ?? selectedServer else { return .refuse("No server mounted") }
        let body = SilenceBuilder.silence(labels: alert.labels, duration: duration, comment: comment)
        do {
            let created = try await client(for: server).createSilence(body, org: alert.orgId)
            await refresh()
            let until = Date().addingTimeInterval(duration.seconds).formatted(date: .omitted, time: .shortened)
            return .pass("Silence \(created.silenceID.prefix(8)) on \(server.name) until \(until)")
        } catch {
            record("POST /api/alertmanager/grafana/api/v2/silences", error)
            return .refuse(error.localizedDescription)
        }
    }

    // MARK: Push

    /// The server the relay files this phone under: the mounted one when it is signed in, else any signed-in one.
    private func serverForPush() async -> Server? {
        if let server = selectedServer, await credentials.isSignedIn(server) { return server }
        for server in store.servers where await credentials.isSignedIn(server) { return server }
        return nil
    }

    func registerPush() async {
        guard let token = push.deviceToken, let relay = store.relayURL else { return }
        guard let server = await serverForPush() else {
            push.registration = .refuse("Sign in to a server first; the relay files this phone under your Grafana login")
            return
        }
        push.registration = .pending
        do {
            let credential = try await credentials.credential(for: server)
            let result = try await RelayClient(baseURL: relay)
                .register(token: token, environment: PushManager.apnsEnvironment, name: UIDevice.current.name, server: server, credential: credential, prefs: notificationPrefs(for: server))
            push.registeredAs = result.user
            push.registration = .pass(Date())
            push.preferences = .pass(Date())
        } catch {
            push.registration = .refuse(error.localizedDescription)
            record("POST \(relay.host ?? "relay")/devices", error)
        }
    }

    private func deregisterPush(using server: Server) async {
        guard let token = push.deviceToken, let relay = store.relayURL,
              let credential = try? await credentials.credential(for: server) else { return }
        do {
            try await RelayClient(baseURL: relay).deregister(token: token, server: server, credential: credential)
            push.registration = .none
            push.registeredAs = nil
        } catch {
            record("DELETE \(relay.host ?? "relay")/devices", error)
        }
    }

    func handlePush(_ payload: BrazierPush, action: String?) async {
        let server = store.servers.first { $0.url.host == payload.externalHost } ?? selectedServer ?? store.servers.first
        if let action, let hours = PushManager.actions.first(where: { $0.id == action })?.hours {
            guard let server, let duration = SilenceDuration(rawValue: hours) else { return }
            let result = await silence(alert: payload.asAlert, duration: duration, comment: "Silenced from Brazier", on: server)
            switch result {
            case .pass(let what): PushManager.notifyOutcome(title: "Silenced \(payload.alertname)", body: what)
            case .refuse(let why): PushManager.notifyOutcome(title: "Could not silence \(payload.alertname)", body: why)
            }
            return
        }
        if let server, server.id != selectedServerID { select(server) }
        if let orgId = payload.orgId, case .one(let current) = orgSelection, current != orgId {
            orgSelection = .one(orgId)
        }
        pendingAlert = payload.asAlert
    }

    // MARK: Notification preferences

    func notificationPrefs(for server: Server) -> NotificationPrefs {
        guard let data = UserDefaults.standard.data(forKey: "notificationPrefs.\(server.id.uuidString)"),
              let prefs = try? JSONDecoder().decode(NotificationPrefs.self, from: data) else { return NotificationPrefs() }
        return prefs
    }

    /// Kept at once; handed to the relay after a short pause, so a run of taps is one call.
    func setNotificationPrefs(_ prefs: NotificationPrefs, for server: Server) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: "notificationPrefs.\(server.id.uuidString)")
        }
        prefsSync?.cancel()
        prefsSync = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await syncPreferences(for: server)
        }
    }

    func syncPreferences(for server: Server) async {
        guard let token = push.deviceToken, let relay = store.relayURL else { return }
        guard await credentials.isSignedIn(server) else {
            push.preferences = .refuse("Sign in to \(server.name) first")
            return
        }
        push.preferences = .pending
        do {
            let credential = try await credentials.credential(for: server)
            _ = try await RelayClient(baseURL: relay).setPreferences(token: token, prefs: notificationPrefs(for: server), server: server, credential: credential)
            push.preferences = .pass(Date())
        } catch {
            push.preferences = .refuse(error.localizedDescription)
            record("PUT \(relay.host ?? "relay")/devices/…/preferences", error)
        }
    }

    // MARK: Fault rail

    func record(_ call: String, _ error: Error) {
        faults.insert(Fault(at: Date(), call: call, reason: error.localizedDescription), at: 0)
        if faults.count > 50 { faults.removeLast(faults.count - 50) }
    }

    func keep(_ fault: Fault) {
        guard let i = faults.firstIndex(where: { $0.id == fault.id }) else { return }
        faults[i].kept = true
    }

    var unkeptFaults: [Fault] { faults.filter { !$0.kept } }
}
