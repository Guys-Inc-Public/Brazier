import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var relayText = ""
    @State private var registering = false
    @State private var testing = false
    @State private var relayHealth: RelayHealth?
    @State private var relayFault: String?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private var relayURL: URL? {
        if case .url(let url) = ServerAddress.normalise(relayText) { return url }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ServersView() } label: {
                        HStack(spacing: Brand.Space.label) {
                            Text("Servers").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                            Spacer()
                            Text("\(model.store.servers.count)").font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                        }
                        .frame(minHeight: Brand.hitTarget)
                    }
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparatorTint(Brand.Tone.line)
                } header: { Eyebrow("servers").textCase(nil) }

                Section {
                    relayField
                    row("Permission") { StateChip(word: model.push.authorizationWord, signal: model.push.authorizationSignal) }
                    if model.push.authorization == .notDetermined {
                        Button("Allow notifications") { Task { _ = await model.push.requestPermission() } }
                            .buttonStyle(ThrowButtonStyle())
                            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    }
                    row("Device token") {
                        if let token = model.push.deviceToken {
                            Text("\(token.prefix(8))…\(token.suffix(6))").font(BrandFont.code).foregroundStyle(Brand.Tone.paper)
                        } else {
                            StateChip(word: "NONE", signal: .none)
                        }
                    }
                    row("Environment") { Text(PushManager.apnsEnvironment).font(BrandFont.code).foregroundStyle(Brand.Tone.paper) }
                    row("Registration") {
                        switch model.push.registration {
                        case .none: StateChip(word: "NOT SENT", signal: .none)
                        case .pending: StateChip(word: "PENDING", signal: .wait)
                        case .pass(let at): StateChip(word: "PASS \(at.formatted(date: .omitted, time: .standard))", signal: .ok)
                        case .refuse: StateChip(word: "REFUSE", signal: .stop)
                        }
                    }
                    if let who = model.push.registeredAs {
                        row("Filed under") { Text(who).font(BrandFont.code).foregroundStyle(Brand.Tone.paper) }
                    }
                    if case .refuse(let why) = model.push.registration {
                        Text(why).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    }
                    if model.push.deviceToken == nil {
                        Interlock(reason: "No device token yet; allow notifications first")
                            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    } else if relayURL == nil {
                        Interlock(reason: "Enter a relay address to register this phone")
                            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    } else {
                        Button(registering ? "Registering…" : "Register this phone with the relay") {
                            guard !registering else { return }
                            registering = true
                            model.store.relayURL = relayURL
                            Task { await model.registerPush(); registering = false }
                        }
                        .buttonStyle(ThrowButtonStyle(primary: false))
                        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    }
                } header: { Eyebrow("push").textCase(nil) }

                if !model.faults.isEmpty {
                    Section {
                        ForEach(model.faults.prefix(20)) { fault in
                            FaultCard(fault: fault)
                                .opacity(fault.kept ? 0.55 : 1)
                                .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                        }
                    } header: { Eyebrow("faults this session").textCase(nil) }
                }

                Section {
                    row("Version") { Text(version).font(BrandFont.code).foregroundStyle(Brand.Tone.paper) }
                    row("Licence") { Text("MIT").font(BrandFont.code).foregroundStyle(Brand.Tone.paper) }
                    Link(destination: URL(string: "https://github.com/Guys-Inc-Public/Brazier")!) {
                        row("Source") { HStack { Text("Guys-Inc-Public/Brazier").font(BrandFont.code).foregroundStyle(Brand.Tone.hot); Image(systemName: "arrow.up.right").foregroundStyle(Brand.Tone.hot) } }
                    }
                    .listRowBackground(Brand.Tone.ink).listRowSeparatorTint(Brand.Tone.line)
                    Text(Brand.notAffiliated).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    Text("Fonts: Archivo and Martian Mono, SIL Open Font License 1.1.").font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                } header: { Eyebrow("about").textCase(nil) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.Tone.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { HeaderMark() } }
            .task {
                relayText = model.store.relayURL?.absoluteString ?? ""
                await model.push.refreshAuthorization()
            }
        }
    }

    /// The relay address, a test against its /health, and the one line of what a relay is.
    private var relayField: some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            Eyebrow("relay address")
            HStack(spacing: Brand.Space.inline) {
                TextField("https://relay.example.com", text: $relayText)
                    .fieldChrome().keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(saveRelay)
                if testing {
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
            Text("A small relay run by whoever runs your Grafana; it receives Grafana's webhook and hands each alert to Apple. Leave it empty and alerts still read whenever the app is open.")
                .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        }
        .padding(.vertical, Brand.Space.inline)
        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
    }

    private func saveRelay() {
        model.store.relayURL = relayURL
        relayHealth = nil
        relayFault = nil
    }

    private func testRelay() {
        guard let url = relayURL else { return }
        saveRelay()
        testing = true
        Task {
            do { relayHealth = try await RelayClient(baseURL: url).health(); relayFault = nil }
            catch { relayHealth = nil; relayFault = error.localizedDescription }
            testing = false
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Brand.Space.label) {
            Text(label).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            Spacer()
            content()
        }
        .frame(minHeight: Brand.hitTarget)
        .listRowBackground(Brand.Tone.ink)
        .listRowSeparatorTint(Brand.Tone.line)
    }
}
