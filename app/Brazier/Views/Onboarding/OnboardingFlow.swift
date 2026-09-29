import SwiftUI
import Observation

enum SetupMethod: Equatable {
    case session, token, oidc

    var word: String {
        switch self {
        case .session: return "SESSION"
        case .token: return "TOKEN"
        case .oidc: return "OIDC"
        }
    }
}

/// Everything the walkthrough learns before the server exists. Secrets stay here only until saved.
@Observable
final class SetupDraft {
    var urlText = ""
    var url: URL?
    var health: ServerProbe.Outcome?
    /// The address text the current health reading belongs to.
    var checkedText = ""
    var relayText = ""
    var relayHealth: RelayHealth?
    var relayDirectory: RelayDirectory?
    var testedRelayText = ""
    /// What the admin's signpost said for the checked address; nil until a check has run it.
    var discovery: DiscoveryState?
    /// The address text the discovery reading belongs to.
    var discoveredText = ""
    /// What the Grafana's own sign-in page offers, read for the checked address.
    var shape: ServerProbe.SignInShape?
    var shapedText = ""
    var method: SetupMethod?
    var user: GrafanaUser?
    /// The whole Cookie header a sign-in produced, Grafana's session and any gate's cookie beside it.
    var sessionCookie: String?
    var sessionExpiry: String?
    var username = ""
    var password = ""
    var apiToken = ""
    var oidcIssuer: URL?
    var oidcClientID = ""
    var providerName: String?
    var oidcTokens: TokenResponse?
    var notificationsGranted: Bool?
    var savedServer: Server?
    #if DEBUG
    var debugOpenWeb = false
    #endif

    var name: String { url?.host ?? "Grafana" }

    var relayURL: URL? {
        if case .url(let url) = ServerAddress.normalise(relayText) { return url }
        return nil
    }

    var relayTested: Bool { relayHealth?.ok == true && testedRelayText == relayText && relayURL != nil }

    /// The sign-in shape for the checked address, if the address has not moved on since.
    var currentShape: ServerProbe.SignInShape? {
        guard let shape, shapedText == checkedText, !checkedText.isEmpty else { return nil }
        return shape
    }

    /// What was found for the checked address, if the address has not moved on since.
    var discovered: Discovery.Result? {
        guard case .found(let result) = discovery, discoveredText == checkedText else { return nil }
        return result
    }

    /// How this Grafana signs in, if anything says: the tested relay's directory first, then the signpost.
    var published: RelayDirectory.SignIn? {
        guard let url else { return nil }
        let origin = ServerAddress.origin(of: url)
        if relayTested, let signIn = relayDirectory?.signIn(for: origin) { return signIn }
        return discovered?.signIn
    }

    var authMode: Server.AuthMode? {
        switch method {
        case .session: return .session
        case .token: return .token
        case .oidc:
            guard let oidcIssuer else { return nil }
            return .oidc(issuer: oidcIssuer, clientID: oidcClientID)
        case nil: return nil
        }
    }

    /// The address changed: whatever was verified against the old one no longer counts.
    func resetVerification() {
        method = nil
        user = nil
        sessionCookie = nil
        sessionExpiry = nil
        password = ""
        oidcTokens = nil
        oidcIssuer = nil
        oidcClientID = ""
        providerName = nil
    }

    enum DiscoveryState: Equatable {
        case looking, found(Discovery.Result), nothing
    }

    /// After a reachable health reading: read how the Grafana signs in, ask the admin's signpost, then
    /// test any relay it names so the step can show the relay's own answer. A relay the person typed
    /// themselves is left alone. A Grafana behind a gate still gets the DNS signpost.
    func discover() async {
        guard let url, let health, health.isReachable else { return }
        let text = checkedText
        async let shaped = ServerProbe.shape(url, fronted: health.isFronted)
        let previous = discovered?.relayURL?.absoluteString
        discovery = .looking
        discoveredText = text
        let found = await Discovery.find(for: url)
        if checkedText == text {
            var stillHere = true
            if let relay = found?.relayURL, relayText.isEmpty || relayText == previous {
                relayText = relay.absoluteString
                let client = RelayClient(baseURL: relay)
                relayHealth = try? await client.health()
                relayDirectory = try? await client.directory()
                testedRelayText = relayText
                stillHere = checkedText == text
            }
            if stillHere { discovery = found.map { .found($0) } ?? .nothing }
        }
        let result = await shaped
        if checkedText == text {
            shape = result
            shapedText = text
        }
    }
}

/// First run: welcome, server and relay, sign in, notifications, done. From Servers, the same minus welcome.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    let includeWelcome: Bool
    let onFinished: () -> Void
    @State private var draft = SetupDraft()
    @State private var step: Step

    enum Step: Int, Comparable {
        case welcome, server, signIn, notifications, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        /// Welcome is a cover, not a step; the four steps count from the address.
        var number: Int? { self == .welcome ? nil : rawValue }
    }

    init(includeWelcome: Bool, onFinished: @escaping () -> Void) {
        self.includeWelcome = includeWelcome
        self.onFinished = onFinished
        _step = State(initialValue: includeWelcome ? .welcome : .server)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .welcome:
                    WelcomeStep { go(.server) }
                case .server:
                    ServerStep(draft: draft, back: includeWelcome ? { go(.welcome) } : nil) { go(.signIn) }
                case .signIn:
                    SignInStep(draft: draft, back: { go(.server) }) { go(.notifications) }
                case .notifications:
                    NotificationsStep(draft: draft, back: { go(.signIn) }) { _ in
                        Task { await save(); go(.done) }
                    }
                case .done:
                    DoneStep(draft: draft, onFinished: onFinished)
                }
            }
            .id(step)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Brand.Tone.ink.ignoresSafeArea())
        .animation(Brand.Motion.curve, value: step)
        #if DEBUG
        .task { await debugJump() }
        #endif
    }

    private var header: some View {
        HStack {
            HeaderMark()
            Spacer()
            if let n = step.number { Eyebrow("step \(n) of 4", tone: step == .done ? Brand.Tone.ok : Brand.Tone.muted) }
        }
        .padding(.horizontal, Brand.Space.card)
        .padding(.vertical, Brand.Space.label)
    }

    private func go(_ next: Step) {
        withAnimation(Brand.Motion.curve) { step = next }
    }

    private func save() async {
        guard let url = draft.url, let method = draft.method, let auth = draft.authMode else { return }
        let server = Server(name: draft.name, url: url, auth: auth)
        let login = draft.user?.login
        switch method {
        case .session:
            await model.add(server, session: (cookie: draft.sessionCookie ?? "", expiry: draft.sessionExpiry), login: login)
        case .token:
            await model.add(server, apiToken: draft.apiToken, login: login)
        case .oidc:
            await model.add(server, tokens: draft.oidcTokens, login: login)
        }
        if let relay = draft.relayURL { model.store.relayURL = relay }
        draft.savedServer = server
        model.select(server)
        await model.push.refreshAuthorization()
        await model.registerPush()
    }
}

#if DEBUG
extension OnboardingFlow {
    /// Development only: `simctl launch` with SIMCTL_CHILD_BRAZIER_SHOT=server|signin|signedin|web|notifications|done
    /// opens the walkthrough at that step with the real checks already run (BRAZIER_SHOT_URL, _TOKEN, _RELAY
    /// feed the fields), so a headless build host can screenshot each step. Never needed by a person.
    fileprivate func debugJump() async {
        let env = ProcessInfo.processInfo.environment
        guard let shot = env["BRAZIER_SHOT"], shot != "welcome",
              let raw = env["BRAZIER_SHOT_URL"], case .url(let url) = ServerAddress.normalise(raw) else { return }
        draft.urlText = url.absoluteString
        draft.url = url
        draft.health = await ServerProbe.health(url)
        draft.checkedText = draft.urlText
        Discovery.selfCheck()
        ServerProbe.selfCheck()
        await draft.discover()
        if let relayRaw = env["BRAZIER_SHOT_RELAY"], !relayRaw.isEmpty {
            draft.relayText = relayRaw
            if let relay = draft.relayURL {
                let client = RelayClient(baseURL: relay)
                draft.relayHealth = try? await client.health()
                draft.relayDirectory = try? await client.directory()
                draft.testedRelayText = draft.relayText
            }
        }
        if shot == "server" { go(.server); return }
        if let token = env["BRAZIER_SHOT_TOKEN"], let user = try? await ServerProbe.user(url, credential: .bearer(token)) {
            draft.apiToken = token
            draft.user = user
            draft.method = .token
        }
        switch shot {
        case "signin":
            draft.resetVerification()
            go(.signIn)
        case "signedin":
            // BRAZIER_SHOT_USER and _PASSWORD: Grafana's own form, for the signed-in plate.
            if let name = env["BRAZIER_SHOT_USER"], let password = env["BRAZIER_SHOT_PASSWORD"],
               let result = try? await ServerProbe.passwordSignIn(url, user: name, password: password) {
                draft.username = name
                draft.sessionCookie = result.cookieHeader
                draft.sessionExpiry = result.expiry
                draft.user = result.user
                draft.method = .session
            }
            go(.signIn)
        case "web":
            draft.resetVerification()
            draft.debugOpenWeb = true
            go(.signIn)
        case "notifications":
            go(.notifications)
        case "done":
            await save()
            go(.done)
        default:
            break
        }
    }
}
#endif
