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
    var method: SetupMethod?
    var user: GrafanaUser?
    var sessionCookie: String?
    var sessionExpiry: String?
    var apiToken = ""
    var issuerText = ""
    var clientID = ""
    var oidcTokens: TokenResponse?
    /// The address text the current health reading belongs to.
    var checkedText = ""
    var relayText = ""
    var relayHealth: RelayHealth?
    var testedRelayText = ""
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

    var authMode: Server.AuthMode? {
        switch method {
        case .session: return .session
        case .token: return .token
        case .oidc:
            guard let issuer = URL(string: issuerText) else { return nil }
            return .oidc(issuer: issuer, clientID: clientID)
        case nil: return nil
        }
    }

    /// The address changed: whatever was verified against the old one no longer counts.
    func resetVerification() {
        method = nil
        user = nil
        sessionCookie = nil
        sessionExpiry = nil
        oidcTokens = nil
    }
}

/// First run: welcome, server, sign in, notifications, done. From Servers, the same minus welcome.
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
                    NotificationsStep(draft: draft, back: { go(.signIn) }) { asked in
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
    /// Development only: `simctl launch` with SIMCTL_CHILD_BRAZIER_SHOT=server|signin|web|notifications|done
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
        if shot == "server" { go(.server); return }
        if let token = env["BRAZIER_SHOT_TOKEN"], let user = try? await ServerProbe.user(url, credential: .bearer(token)) {
            draft.apiToken = token
            draft.user = user
            draft.method = .token
        }
        draft.relayText = env["BRAZIER_SHOT_RELAY"] ?? ""
        switch shot {
        case "signin":
            draft.resetVerification()
            go(.signIn)
        case "web":
            draft.resetVerification()
            draft.debugOpenWeb = true
            go(.signIn)
        case "notifications":
            if let relay = draft.relayURL {
                draft.relayHealth = try? await RelayClient(baseURL: relay).health()
                draft.testedRelayText = draft.relayText
            }
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
