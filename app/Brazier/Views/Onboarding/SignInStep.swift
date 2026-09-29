import SwiftUI

/// Step 2: three ways in, in the order most people should try them. Continue needs a verified user.
struct SignInStep: View {
    @Bindable var draft: SetupDraft
    let back: () -> Void
    let next: () -> Void

    @State private var showWeb = false
    @State private var busy = false
    @State private var latch: ThrowResult?
    @State private var tokenOpen = false
    @State private var advancedOpen = false

    var body: some View {
        StepPage(title: "Sign in to \(draft.name)", lead: "Sign in the way you already do. Brazier keeps only the session, in this phone's keychain.") {
            if let latch { LatchView(result: latch) { self.latch = nil } }
            if let user = draft.user {
                signedInPlate(user)
            } else {
                methods
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

    private var methods: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            MethodCard(title: "Sign in with Grafana", chip: "recommended",
                       text: "Grafana's own sign-in page opens here. If your Grafana uses single sign-on, the page takes you there and back.") {
                Button("Open the sign-in page") { showWeb = true }
                    .buttonStyle(ThrowButtonStyle())
            }
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
            MethodCard(title: "Advanced · single sign-on for the app",
                       text: "The app signs in at your identity provider as its own public client (PKCE) and hands Grafana the ID token. Your Grafana admin must have JWT auth pointed at that provider.",
                       open: $advancedOpen) {
                VStack(alignment: .leading, spacing: Brand.Space.inline) {
                    TextField("Issuer URL", text: $draft.issuerText).fieldChrome()
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Client id", text: $draft.clientID).fieldChrome()
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if URL(string: draft.issuerText)?.host == nil || draft.clientID.isEmpty {
                        Interlock(reason: "Enter the issuer and client id")
                    } else {
                        Button("Sign in with the provider", action: signInWithProvider).buttonStyle(ThrowButtonStyle(primary: false))
                    }
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

    private func signInWithProvider() {
        guard let url = draft.url, let issuer = URL(string: draft.issuerText.trimmingCharacters(in: .whitespaces)) else { return }
        let clientID = draft.clientID.trimmingCharacters(in: .whitespaces)
        busy = true
        Task {
            do {
                let tokens = try await OIDC.signIn(issuer: issuer, clientID: clientID)
                guard let idToken = tokens.idToken else { throw OIDCError.noIDToken }
                let user = try await ServerProbe.user(url, credential: .jwt(idToken))
                draft.oidcTokens = tokens
                draft.user = user
                draft.method = .oidc
                latch = nil
            } catch OIDCError.cancelled {
                latch = .refuse("Sign-in cancelled")
            } catch is AuthError {
                latch = .refuse("The provider signed you in, but Grafana rejected the ID token. Its JWT auth must trust this provider.")
            } catch {
                latch = .refuse(error.localizedDescription)
            }
            busy = false
        }
    }
}
