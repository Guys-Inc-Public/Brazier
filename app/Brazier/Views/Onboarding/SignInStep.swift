import SwiftUI

/// Step 2: the way in. When the relay published a provider for this Grafana, the system sign-in sheet
/// leads, because passkeys work there and not in a page inside the app. Continue needs a verified user.
struct SignInStep: View {
    @Bindable var draft: SetupDraft
    let back: () -> Void
    let next: () -> Void

    @State private var showWeb = false
    @State private var busy = false
    @State private var latch: ThrowResult?
    @State private var tokenOpen = false
    @State private var pageOpen = false

    private static let pageNote = "For a Grafana that signs in with a password. Single sign-on that needs a passkey does not work here."

    var body: some View {
        StepPage(title: "Sign in to \(draft.name)", lead: "Sign in the way you already do. Brazier keeps only the session, in this phone's keychain.") {
            if let latch { LatchView(result: latch) { self.latch = nil } }
            if let user = draft.user {
                signedInPlate(user)
            } else if let published = draft.published {
                providerFirst(published)
            } else {
                pageFirst
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

    /// The relay named the provider: one obvious button into the system sheet, the rest folded away.
    private func providerFirst(_ signIn: RelayDirectory.SignIn) -> some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            MethodCard(title: "Sign in with \(signIn.displayName)", chip: "recommended",
                       text: "Opens the system sign-in sheet at \(signIn.issuer.host ?? "your provider"); passkeys and Face ID work there.") {
                Button("Sign in with \(signIn.displayName)") { signInWithProvider(signIn) }
                    .buttonStyle(ThrowButtonStyle())
            }
            tokenCard
            MethodCard(title: "Sign in on your Grafana's page", text: Self.pageNote, open: $pageOpen) {
                Button("Open the sign-in page") { showWeb = true }
                    .buttonStyle(ThrowButtonStyle(primary: false))
            }
        }
    }

    /// No relay, or one that does not know this Grafana: Grafana's own page leads.
    private var pageFirst: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            MethodCard(title: "Sign in on your Grafana's page", chip: "recommended",
                       text: "Grafana's own sign-in page opens here. " + Self.pageNote) {
                Button("Open the sign-in page") { showWeb = true }
                    .buttonStyle(ThrowButtonStyle())
            }
            tokenCard
        }
    }

    private var tokenCard: some View {
        MethodCard(title: "Service account token", text: "For a Grafana without a browser sign-in, or for a read-only watcher.", open: $tokenOpen) {
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
