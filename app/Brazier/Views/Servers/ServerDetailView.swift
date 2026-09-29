import SwiftUI

/// One unit pulled forward: probe it, sign in or out, mount it, or remove it under a guard.
struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let serverID: UUID

    @State private var probe: ProbeResult?
    @State private var probing = false
    @State private var latch: ThrowResult?
    @State private var busy = false
    @State private var newToken = ""
    @State private var signedIn = false
    @State private var who: String?
    @State private var showWeb = false
    @State private var issuerText = ""
    @State private var clientID = ""
    @State private var relayText = ""
    @State private var relayHealth: RelayHealth?
    @State private var relayFault: String?
    @State private var relayTesting = false
    @State private var relayLooking = false
    @State private var relaySaving = false

    private var server: Server? { model.store.server(id: serverID) }

    private var providerReady: Bool {
        URL(string: issuerText.trimmingCharacters(in: .whitespaces))?.host != nil && !clientID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var relayTyped: Bool { !relayText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var relayURL: URL? {
        if case .url(let url) = ServerAddress.normalise(relayText) { return url }
        return nil
    }

    /// The field holds something other than what the server has.
    private func relayChanged(_ server: Server) -> Bool {
        (relayURL?.absoluteString ?? "") != (server.relay?.absoluteString ?? "")
    }

    var body: some View {
        if let server {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Space.card) {
                    VStack(alignment: .leading, spacing: Brand.Space.inline) {
                        HStack(spacing: Brand.Space.inline) {
                            StateChip(word: server.authWord, signal: .none)
                            StateChip(word: server.isAnonymous ? "VISITOR" : (signedIn ? "SIGNED IN" : "SIGNED OUT"), signal: signedIn ? .ok : .none)
                            if server.id == model.selectedServerID { StateChip(word: "MOUNTED", signal: .ok) }
                        }
                        Text(server.name).font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
                        Text(server.url.absoluteString).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                        if let who { Eyebrow("as \(who)") }
                    }
                    if let latch {
                        LatchView(result: latch) { self.latch = nil }
                    }
                    Labelled("probe") {
                        if probing {
                            HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("probing") }.frame(minHeight: Brand.hitTarget)
                        } else {
                            Button("Probe") {
                                probing = true
                                Task { probe = await model.probe(server); probing = false }
                            }
                            .buttonStyle(ThrowButtonStyle(primary: false))
                        }
                        if let probe {
                            KeyValueRowsWithLamps(rows: [
                                ("/api/health", probe.healthWord, probe.health),
                                ("/api/user", probe.userWord, probe.user),
                            ])
                        }
                    }
                    Labelled("session · \(server.authMethodName)") {
                        if busy {
                            HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("working") }.frame(minHeight: Brand.hitTarget)
                        } else {
                            switch server.auth {
                            case .session:
                                Button(signedIn ? "Sign in again" : "Sign in") { showWeb = true }
                                    .buttonStyle(ThrowButtonStyle())
                            case .anonymous:
                                Text("Read as a visitor: no silences, no stars, no push. Sign in on Grafana's page to become someone; a provider that needs a passkey goes through the advanced sign-in below.")
                                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                                Button("Sign in on the page") { showWeb = true }
                                    .buttonStyle(ThrowButtonStyle())
                            case .oidc(let issuer, _):
                                Text("Through \(issuer.host ?? "the provider"), in the system sign-in sheet.")
                                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                                Button(signedIn ? "Sign in again" : "Sign in") {
                                    busy = true
                                    Task { latch = await model.signIn(server); await reload(); busy = false }
                                }
                                .buttonStyle(ThrowButtonStyle())
                            case .token:
                                SecureField("New service-account token", text: $newToken).fieldChrome()
                                if newToken.isEmpty {
                                    Interlock(reason: "Paste a token to replace the stored one")
                                } else {
                                    Button("Save token") {
                                        Task { latch = await model.saveToken(newToken, for: server); newToken = ""; await reload() }
                                    }
                                    .buttonStyle(ThrowButtonStyle())
                                }
                            }
                            if signedIn, !server.isAnonymous {
                                Button("Sign out") {
                                    busy = true
                                    Task { await model.signOut(server); await reload(); busy = false }
                                }
                                .buttonStyle(ThrowButtonStyle(primary: false))
                            }
                        }
                    }
                    if server.id != model.selectedServerID {
                        Button("Mount \(server.name)") { model.select(server) }
                            .buttonStyle(ThrowButtonStyle(primary: false))
                    }
                    Labelled("push relay") { relaySection(server) }
                    Labelled("advanced sign-in") {
                        Text("Only if your admin has Grafana's JWT auth pointed at an identity provider and gave you these. The app then signs in there as its own public client and hands Grafana the ID token.")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                        TextField("Issuer URL", text: $issuerText).fieldChrome()
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Client id", text: $clientID).fieldChrome()
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if busy {
                            EmptyView()
                        } else if !providerReady {
                            Interlock(reason: "Enter the issuer and client id")
                        } else {
                            Button("Sign in with the provider") { switchToProvider(server) }
                                .buttonStyle(ThrowButtonStyle(primary: false))
                        }
                    }
                    Labelled("remove") {
                        GuardedThrow(verb: "Remove", cutList: cutList(for: server)) {
                            Task { await model.remove(server); dismiss() }
                        }
                    }
                }
                .padding(Brand.Space.card)
            }
            .background(Brand.Tone.ink)
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await reload() }
            .fullScreenCover(isPresented: $showWeb) {
                GrafanaLoginSheet(server: server.url) { cookie, expiry, user in
                    showWeb = false
                    busy = true
                    Task {
                        latch = await model.completeSessionSignIn(server, cookie: cookie, expiry: expiry, user: user)
                        await reload()
                        busy = false
                    }
                }
            }
        } else {
            BlankBay(title: "Removed", text: "This server is no longer in the list.")
        }
    }

    /// The relay for this Grafana: what the signpost names, or what the admin gave. Test reads its
    /// health; Save hands this phone over to it (and takes it back from the old one).
    @ViewBuilder private func relaySection(_ server: Server) -> some View {
        Text("A small relay run by whoever runs this Grafana; it receives Grafana's webhook and hands each alert to Apple. Each Grafana may have its own. Without one, alerts still read whenever the app is open.")
            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        HStack(spacing: Brand.Space.inline) {
            TextField("https://relay.example.com", text: $relayText)
                .fieldChrome().keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit { testRelay() }
            if relayTesting {
                MeterBridge().frame(width: 60)
            } else {
                Button("Test", action: testRelay).buttonStyle(MomentaryButtonStyle())
                    .disabled(relayURL == nil).opacity(relayURL == nil ? 0.4 : 1)
            }
        }
        if let relayHealth {
            ReadingLine(signal: relayHealth.ok ? .ok : .wait, text: "Relay \(relayHealth.version ?? "") · \(relayHealth.ok ? "ok" : "not ok")\(relayHealth.apns == false ? " · push key not set yet" : "")")
        } else if let relayFault {
            ReadingLine(signal: .stop, text: relayFault)
        }
        HStack(spacing: Brand.Space.label) {
            if relayLooking {
                HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("asking the signpost") }.frame(minHeight: Brand.hitTarget)
            } else {
                Button("Look up") { lookUpRelay(server) }.buttonStyle(MomentaryButtonStyle())
            }
            Spacer()
            if relaySaving {
                HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("saving") }.frame(minHeight: Brand.hitTarget)
            } else if relayTyped, relayURL == nil {
                Interlock(reason: "That address does not parse; it needs https://")
            } else if relayChanged(server) {
                Button(relayTyped ? "Save and register" : "Remove relay") { saveRelay(server) }.buttonStyle(ThrowButtonStyle(primary: relayTyped))
            } else if server.relay != nil {
                registrationLine(server)
            }
        }
    }

    @ViewBuilder private func registrationLine(_ server: Server) -> some View {
        switch model.push.registration(for: server.id) {
        case .pass: StateChip(word: "PHONE REGISTERED", signal: .ok)
        case .pending: StateChip(word: "REGISTERING", signal: .wait)
        case .refuse: StateChip(word: "NOT REGISTERED", signal: .stop)
        case .none: StateChip(word: model.push.deviceToken == nil ? "NOTIFICATIONS OFF" : "NOT SENT", signal: .none)
        }
    }

    private func testRelay() {
        guard let url = relayURL else { return }
        relayTesting = true
        Task {
            do { relayHealth = try await RelayClient(baseURL: url).health(); relayFault = nil }
            catch { relayHealth = nil; relayFault = error.localizedDescription }
            relayTesting = false
        }
    }

    /// Asks this Grafana's signpost (its /.well-known/brazier, else the DNS record) which relay serves it.
    private func lookUpRelay(_ server: Server) {
        relayLooking = true
        Task {
            if let relay = await Discovery.find(for: server.url)?.relayURL {
                relayText = relay.absoluteString
                relayHealth = nil
                relayFault = nil
                testRelay()
            } else {
                relayFault = "No relay is published for \(server.host); ask its admin for the address."
                relayHealth = nil
            }
            relayLooking = false
        }
    }

    private func saveRelay(_ server: Server) {
        relaySaving = true
        Task {
            await model.setRelay(relayURL, for: server)
            relaySaving = false
            if relayURL == nil { relayHealth = nil; relayFault = nil }
        }
    }

    /// Sign in at the provider; only when Grafana accepts the ID token does the server switch to that mode.
    private func switchToProvider(_ server: Server) {
        guard let issuer = URL(string: issuerText.trimmingCharacters(in: .whitespaces)) else { return }
        var updated = server
        updated.auth = .oidc(issuer: issuer, clientID: clientID.trimmingCharacters(in: .whitespaces))
        busy = true
        Task {
            let result = await model.signIn(updated)
            if case .pass = result {
                model.store.update(updated)
                Keychain.delete(SecretKey.sessionCookie(server.id))
                Keychain.delete(SecretKey.sessionExpiry(server.id))
                Keychain.delete(SecretKey.apiToken(server.id))
                issuerText = ""
                clientID = ""
            }
            latch = result
            await reload()
            busy = false
        }
    }

    private func reload() async {
        guard let server else { return }
        signedIn = await model.credentials.isSignedIn(server)
        who = server.isAnonymous ? nil : (await model.credentials.subjectName(server) ?? (server.id == model.selectedServerID ? model.accountName : nil))
        if relayText.isEmpty, !relayTyped { relayText = server.relay?.absoluteString ?? "" }
    }

    private func cutList(for server: Server) -> [String] {
        var lines = ["\(server.name) leaves the list; its alerts stop showing here."]
        switch server.auth {
        case .session: lines.append("The stored Grafana session for \(server.host) is erased from the keychain.")
        case .oidc: lines.append("The stored sign-in for \(server.host) is erased; a fresh sign-in would be needed.")
        case .token: lines.append("The stored service-account token is erased from the keychain. The token itself stays valid in Grafana.")
        case .anonymous: lines.append("Nothing was stored for it; it was read without signing in.")
        }
        if model.push.deviceToken != nil, let relay = server.relay, !server.isAnonymous {
            lines.append("This phone is deregistered from \(relay.host ?? "the relay") under this server's login; pushes routed to it stop.")
        }
        return lines
    }
}

struct KeyValueRowsWithLamps: View {
    let rows: [(String, String, Signal)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline() }
                HStack(spacing: Brand.Space.label) {
                    Lamp(signal: row.2)
                    Text(row.0).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).frame(width: 110, alignment: .leading)
                    Text(row.1).font(BrandFont.code).foregroundStyle(Brand.Tone.paper).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, Brand.Space.inline)
                .padding(.horizontal, Brand.Space.label)
            }
        }
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }
}
