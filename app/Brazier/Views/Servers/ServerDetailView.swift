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

    private var server: Server? { model.store.server(id: serverID) }

    var body: some View {
        if let server {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Space.card) {
                    VStack(alignment: .leading, spacing: Brand.Space.inline) {
                        HStack(spacing: Brand.Space.inline) {
                            StateChip(word: server.authWord, signal: .none)
                            StateChip(word: signedIn ? "SIGNED IN" : "SIGNED OUT", signal: signedIn ? .ok : .none)
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
                    Labelled("session") {
                        if busy {
                            HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("working") }.frame(minHeight: Brand.hitTarget)
                        } else if server.isOIDC {
                            Button(signedIn ? "Sign in again" : "Sign in") {
                                busy = true
                                Task { latch = await model.signIn(server); await reload(); busy = false }
                            }
                            .buttonStyle(ThrowButtonStyle())
                            if signedIn {
                                Button("Sign out") {
                                    busy = true
                                    Task { await model.signOut(server); await reload(); busy = false }
                                }
                                .buttonStyle(ThrowButtonStyle(primary: false))
                            }
                        } else {
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
                    }
                    if server.id != model.selectedServerID {
                        Button("Mount \(server.name)") { model.select(server) }
                            .buttonStyle(ThrowButtonStyle(primary: false))
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
        } else {
            BlankBay(title: "Removed", text: "This server is no longer in the list.")
        }
    }

    private func reload() async {
        guard let server else { return }
        signedIn = await model.credentials.isSignedIn(server)
        who = await model.credentials.subjectName(server)
    }

    private func cutList(for server: Server) -> [String] {
        var lines = ["\(server.name) leaves the list; its alerts stop showing here."]
        if server.isOIDC {
            lines.append("The stored session for \(server.host) is erased; a fresh sign-in would be needed.")
            if model.push.deviceToken != nil { lines.append("This phone is deregistered from the relay; pushes routed to it stop.") }
        } else {
            lines.append("The stored service-account token is erased from the keychain. The token itself stays valid in Grafana.")
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
