import SwiftUI

/// A bench: the server is probed against the real endpoint before it can be added.
struct AddServerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case oidc = "Sign in (OIDC)"
        case token = "Service-account token"
        var id: String { rawValue }
    }

    @State private var name = ""
    @State private var urlText = "https://"
    @State private var mode: Mode = .oidc
    @State private var issuerText = ""
    @State private var clientID = ""
    @State private var token = ""
    @State private var probing = false
    @State private var probe: ProbeResult?
    @State private var probedURL: URL?

    private var url: URL? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private var issuer: URL? {
        guard mode == .oidc else { return nil }
        return URL(string: issuerText.trimmingCharacters(in: .whitespaces))
    }

    private var blocker: String? {
        if url == nil { return "Enter the Grafana URL" }
        if mode == .oidc && (issuer == nil || clientID.isEmpty) { return "Enter the issuer and client id" }
        if mode == .token && token.isEmpty { return "Paste a service-account token" }
        if probe?.health != .ok || probedURL != url { return "Probe the server first" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Space.card) {
                Labelled("preset") {
                    Button("Use the Guys Inc estate") {
                        name = EstatePreset.name
                        urlText = EstatePreset.grafana.absoluteString
                        mode = .oidc
                        issuerText = EstatePreset.issuer.absoluteString
                        clientID = EstatePreset.clientID
                        probe = nil
                    }
                    .buttonStyle(ThrowButtonStyle(primary: false))
                }
                Labelled("name") {
                    TextField("Home lab", text: $name).fieldChrome()
                }
                Labelled("grafana url") {
                    TextField("https://grafana.example.org", text: $urlText)
                        .fieldChrome()
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Labelled("sign-in") {
                    Picker("Sign-in", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .oidc {
                        Text("The instance's own identity provider issues the token; Grafana trusts it through auth.jwt.")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                        TextField("Issuer URL", text: $issuerText).fieldChrome()
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Client id", text: $clientID).fieldChrome()
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Text("A Grafana service-account token, kept in the keychain.")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                        SecureField("glsa_…", text: $token).fieldChrome()
                    }
                }
                Labelled("probe") {
                    if probing {
                        HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("probing") }
                            .frame(minHeight: Brand.hitTarget)
                    } else if let url {
                        Button("Probe \(url.host ?? "")") {
                            probing = true
                            Task {
                                let target = Server(name: name, url: url, auth: .token)
                                probe = await model.probe(target)
                                probedURL = url
                                probing = false
                            }
                        }
                        .buttonStyle(ThrowButtonStyle(primary: false))
                    } else {
                        Interlock(reason: "Enter a URL to probe")
                    }
                    if let probe, probedURL == url {
                        HStack(spacing: Brand.Space.inline) {
                            Lamp(signal: probe.health)
                            Text(probe.healthWord).font(BrandFont.meta).foregroundStyle(Brand.Tone.paper)
                        }
                    }
                }
                if let blocker {
                    Interlock(reason: blocker)
                } else {
                    Button("Add server") {
                        Task {
                            let auth: Server.AuthMode = mode == .oidc ? .oidc(issuer: issuer!, clientID: clientID) : .token
                            let server = Server(name: name.isEmpty ? (url?.host ?? "Grafana") : name, url: url!, auth: auth)
                            await model.add(server, apiToken: mode == .token ? token : nil)
                            dismiss()
                        }
                    }
                    .buttonStyle(ThrowButtonStyle())
                }
            }
            .padding(Brand.Space.card)
        }
        .background(Brand.Tone.ink)
        .navigationTitle("Add a server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
