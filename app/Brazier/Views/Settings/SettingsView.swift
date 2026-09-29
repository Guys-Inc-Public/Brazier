import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var relayText = ""
    @State private var registering = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var store = model.store
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
                    VStack(alignment: .leading, spacing: Brand.Space.inline) {
                        Eyebrow("relay url")
                        TextField("https://brazier.gicloud.org", text: $relayText)
                            .fieldChrome().keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { if let url = URL(string: relayText) { store.relayURL = url } }
                    }
                    .padding(.vertical, Brand.Space.inline)
                    .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    row("Registration") {
                        switch model.push.registration {
                        case .none: StateChip(word: "NOT SENT", signal: .none)
                        case .pending: StateChip(word: "PENDING", signal: .wait)
                        case .pass(let at): StateChip(word: "PASS \(at.formatted(date: .omitted, time: .standard))", signal: .ok)
                        case .refuse: StateChip(word: "REFUSE", signal: .stop)
                        }
                    }
                    if case .refuse(let why) = model.push.registration {
                        Text(why).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    }
                    if model.push.deviceToken != nil {
                        Button(registering ? "Registering…" : "Register this phone with the relay") {
                            guard !registering else { return }
                            registering = true
                            if let url = URL(string: relayText) { store.relayURL = url }
                            Task { await model.registerPush(); registering = false }
                        }
                        .buttonStyle(ThrowButtonStyle(primary: false))
                        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                    } else {
                        Interlock(reason: "No device token yet; allow notifications first")
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
                relayText = model.store.relayURL.absoluteString
                await model.push.refreshAuthorization()
            }
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
