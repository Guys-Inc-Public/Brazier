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
    private(set) var asOf: Date?
    private(set) var lastFailure: Date?
    private(set) var bay: BayState = .blank
    private(set) var faults: [Fault] = []
    private(set) var signedIn = false
    private(set) var accountName: String?
    var pendingAlert: GrafanaAlert?
    private var refreshing = false
    private var accountNames: [UUID: String] = [:]

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
    private func seedFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["BRAZIER_SEED_URL"], let url = URL(string: raw), let token = env["BRAZIER_SEED_TOKEN"] else { return }
        let server: Server
        if let existing = store.servers.first(where: { $0.url == url }) {
            server = existing
        } else {
            server = Server(name: env["BRAZIER_SEED_NAME"] ?? (url.host ?? "Seeded"), url: url, auth: .token)
            store.add(server)
        }
        selectedServerID = server.id
        do { try Keychain.set(token, for: SecretKey.apiToken(server.id)) }
        catch { record("keychain seed", error) }
        bay = .warming
    }
    #endif

    var selectedServer: Server? { store.server(id: selectedServerID) }

    func client(for server: Server) -> GrafanaClient {
        GrafanaClient(server: server, credentials: credentials)
    }

    // MARK: Mounting and reading

    func select(_ server: Server) {
        selectedServerID = server.id
        alerts = []
        silences = []
        asOf = nil
        lastFailure = nil
        bay = .warming
        Task { await refresh() }
    }

    func refresh() async {
        guard let server = selectedServer else {
            bay = .blank
            return
        }
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
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
            async let alertsRead = client.alerts()
            async let silencesRead = client.silences()
            alerts = try await alertsRead
            silences = (try? await silencesRead) ?? []
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
            let created = try await client(for: server).createSilence(body)
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
                .register(token: token, environment: PushManager.apnsEnvironment, name: UIDevice.current.name, server: server, credential: credential)
            push.registeredAs = result.user
            push.registration = .pass(Date())
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
        pendingAlert = payload.asAlert
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
