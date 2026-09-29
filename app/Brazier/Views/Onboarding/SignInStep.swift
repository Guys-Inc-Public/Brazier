import SwiftUI

/// Step 2: the way in, laid out from what step 1 learned. A provider the admin published leads, because
/// passkeys work in the system sheet and not in a page inside the app. Otherwise Grafana's own
/// username-and-password form leads when the page says it is on; an SSO-only Grafana, or one behind a
/// sign-in gate, leads with its page. A service account token is always there. Continue needs a verified user.
struct SignInStep: View {
    @Bindable var draft: SetupDraft
    let back: () -> Void
    let next: () -> Void

    @State private var showWeb = false
    @State private var busy = false
    @State private var latch: ThrowResult?
    @State private var tokenOpen = false
    @State private var pageOpen = false
    @State private var passwordOpen = false
    @State private var passwordFault: String?
    @FocusState private var focused: Field?

    enum Field { case username, password }

    private enum Lead: Equatable { case provider, password, page }

    private static let pageNote = "For single sign-on through Grafana's page. A provider that needs a passkey does not work here."

    private var shape: ServerProbe.SignInShape? { draft.currentShape }
    private var fronted: Bool { draft.health?.isFronted == true || shape?.fronted == true }
    private var passwordForm: Bool? { shape?.passwordForm }
    /// Hidden only when the page said the form is off; unknown still shows it, folded.
    private var offerPassword: Bool { passwordForm != false }

    private var lead: Lead {
        if draft.published != nil { return .provider }
        if passwordForm != false, !fronted { return .password }
        return .page
    }

    private var canSignInWithPassword: Bool {
        !draft.username.trimmingCharacters(in: .whitespaces).isEmpty && !draft.password.isEmpty
    }

    var body: some View {
        StepPage(title: "Sign in to \(draft.name)", lead: "Sign in the way you already do. Brazier keeps only the session, in this phone's keychain.") {
            if let latch { LatchView(result: latch) { self.latch = nil } }
            if let user = draft.user {
                signedInPlate(user)
            } else {
                cards
            }
        } footer: {
            StepButtons(back: back, primary: "Continue", blocker: draft.user == nil ? "Sign in to continue" : nil, busy: busy, action: next)
        }
        #if DEBUG
        .onAppear { if draft.debugOpenWeb { draft.debugOpenWeb = false; showWeb = true } }
        #endif
        .fullScreenCover(isPresented: $showWeb) {
            if let url = draft.url {
                GrafanaLoginSheet(server: url) { cookie, expiry, user in
                    draft.sessionCookie = cookie
                    draft.sessionExpiry = expiry
                    draft.user = user
                    draft.method = .session
                    latch = nil
                    showWeb = false
                }
            }
        }
    }

    @ViewBuilder private var cards: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            switch lead {
            case .provider:
                if let signIn = draft.published { providerCard(signIn) }
                if offerPassword { passwordCard(leads: false) }
                pageCard(leads: false)
                tokenCard
            case .password:
                passwordCard(leads: true)
                pageCard(leads: false)
                tokenCard
            case .page:
                pageCard(leads: true)
                if offerPassword { passwordCard(leads: false) }
                tokenCard
            }
        }
    }

    private func signedInPlate(_ user: GrafanaUser) -> some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            HStack(spacing: Brand.Space.inline) {
                Lamp(signal: .ok)
                Text("Signed in as \(user.login)").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                Spacer()
                StateChip(word: draft.method?.word ?? "", signal: .ok)
            }
            if !user.name.isEmpty {
                Text(user.name).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
            Button("Use a different way in") { draft.resetVerification() }
                .buttonStyle(MomentaryButtonStyle())
                .padding(.leading, -Brand.Space.inline)
        }
        .padding(Brand.Space.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }

    /// The admin named the provider: one obvious button into the system sheet.
    private func providerCard(_ signIn: RelayDirectory.SignIn) -> some View {
        MethodCard(title: "Sign in with \(signIn.displayName)", chip: "recommended",
                   text: "Opens the system sign-in sheet at \(signIn.issuer.host ?? "your provider"); passkeys and Face ID work there.") {
            Button("Sign in with \(signIn.displayName)") { signInWithProvider(signIn) }
                .buttonStyle(ThrowButtonStyle())
        }
    }

    /// Grafana's own accounts, or LDAP through Grafana: the same POST its page makes, no page needed.
    private func passwordCard(leads: Bool) -> some View {
        MethodCard(title: "Username and password", chip: leads ? "recommended" : nil,
                   text: "Grafana's own accounts, or LDAP through Grafana. Sent to your Grafana and nowhere else.",
                   open: leads ? nil : $passwordOpen) {
            VStack(alignment: .leading, spacing: Brand.Space.inline) {
                TextField("Username or email", text: $draft.username)
                    .fieldChrome()
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                SecureField("Password", text: $draft.password)
                    .fieldChrome()
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSignInWithPassword { signInWithPassword() } }
                if let passwordFault {
                    ReadingLine(signal: .stop, text: passwordFault)
                }
                if !canSignInWithPassword {
                    Interlock(reason: "Enter your username and password")
                } else {
                    Button("Sign in", action: signInWithPassword).buttonStyle(ThrowButtonStyle(primary: leads))
                }
            }
        }
    }

    private var pageText: String {
        if fronted {
            return "Your Grafana sits behind a sign-in page. Sign in there, then on Grafana if it asks; Brazier keeps the cookies it needs."
        }
        if passwordForm == false {
            if let names = shape?.providers, !names.isEmpty {
                return "Your Grafana signs in through \(names.joined(separator: " or ")). That works here unless it needs a passkey."
            }
            if let host = shape?.ssoHost {
                return "Your Grafana signs in through \(host). That works here unless it needs a passkey."
            }
            return "Your Grafana signs in through single sign-on. That works here unless it needs a passkey."
        }
        return lead == .page ? "Grafana's own sign-in page opens here. " + Self.pageNote : Self.pageNote
    }

    private func pageCard(leads: Bool) -> some View {
        MethodCard(title: "Sign in on your Grafana's page", chip: leads ? "recommended" : nil, text: pageText, open: leads ? nil : $pageOpen) {
            Button("Open the sign-in page") { showWeb = true }
                .buttonStyle(ThrowButtonStyle(primary: leads))
        }
    }

    private var tokenCard: some View {
        MethodCard(title: "Service account token", text: "For a Grafana without a browser sign-in, or for a read-only watcher. A sign-in gate in front of Grafana blocks tokens unless it lets /api/ through.", open: $tokenOpen) {
            VStack(alignment: .leading, spacing: Brand.Space.inline) {
                NumberedLine(n: 1, text: "In Grafana: Administration › Users and access › Service accounts › Add service account.")
                NumberedLine(n: 2, text: "Role Viewer to watch, Editor to silence. Then Add service account token.")
                NumberedLine(n: 3, text: "Copy the token (it starts with glsa_) and paste it here.")
                SecureField("glsa_…", text: $draft.apiToken).fieldChrome()
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if draft.apiToken.trimmingCharacters(in: .whitespaces).isEmpty {
                    Interlock(reason: "Paste the token to verify it")
                } else {
                    Button("Verify token", action: verifyToken).buttonStyle(ThrowButtonStyle(primary: false))
                }
            }
        }
    }

    private func signInWithPassword() {
        guard let url = draft.url else { return }
        let user = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        focused = nil
        busy = true
        passwordFault = nil
        Task {
            do {
                let result = try await ServerProbe.passwordSignIn(url, user: user, password: draft.password)
                draft.username = user
                draft.password = ""
                draft.sessionCookie = result.cookieHeader
                draft.sessionExpiry = result.expiry
                draft.user = result.user
                draft.method = .session
                latch = nil
            } catch {
                passwordFault = error.localizedDescription
            }
            busy = false
        }
    }

    private func verifyToken() {
        guard let url = draft.url else { return }
        let token = draft.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task {
            do {
                let user = try await ServerProbe.user(url, credential: .bearer(token))
                draft.apiToken = token
                draft.user = user
                draft.method = .token
                latch = nil
            } catch is AuthError {
                latch = .refuse("Grafana rejected that token. Check it was copied whole and the service account is enabled.")
            } catch {
                latch = .refuse(error.localizedDescription)
            }
            busy = false
        }
    }

    private func signInWithProvider(_ signIn: RelayDirectory.SignIn) {
        guard let url = draft.url else { return }
        busy = true
        Task {
            do {
                let tokens = try await OIDC.signIn(issuer: signIn.issuer, clientID: signIn.clientId)
                guard let idToken = tokens.idToken else { throw OIDCError.noIDToken }
                let user = try await ServerProbe.user(url, credential: .jwt(idToken))
                draft.oidcTokens = tokens
                draft.oidcIssuer = signIn.issuer
                draft.oidcClientID = signIn.clientId
                draft.providerName = signIn.displayName
                draft.user = user
                draft.method = .oidc
                latch = nil
            } catch OIDCError.cancelled {
                latch = .refuse("Sign-in cancelled")
            } catch is AuthError {
                latch = .refuse("\(signIn.displayName) signed you in, but Grafana rejected the ID token. Its JWT auth must trust this provider.")
            } catch {
                latch = .refuse(error.localizedDescription)
            }
            busy = false
        }
    }
}
