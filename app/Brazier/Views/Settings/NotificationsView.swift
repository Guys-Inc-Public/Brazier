import SwiftUI

/// What this phone wants pushed, and the plumbing that gets it there. The choices go to the mounted
/// server's relay, which filters before Apple hears of an alert; they are kept here too, per server.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @State private var prefs = NotificationPrefs()
    @State private var quietOn = false
    @State private var quietStart = NotificationsView.time(22, 0)
    @State private var quietEnd = NotificationsView.time(7, 0)
    @State private var allowPage = true
    @State private var registering = false
    @State private var loaded = false

    private var server: Server? { model.selectedServer }

    var body: some View {
        List {
            Section {
                if let server {
                    whatToSend(server)
                } else {
                    Interlock(reason: "Mount a server first; the choices are kept per server")
                        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
                }
            } header: { Eyebrow("what to send").textCase(nil) }

            Section {
                delivery
            } header: { Eyebrow("delivery").textCase(nil) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.Tone.ink)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.push.refreshAuthorization()
            load()
        }
        .onChange(of: prefs) { _, new in
            guard loaded, let server else { return }
            model.setNotificationPrefs(new, for: server)
        }
        .onChange(of: quietOn) { _, _ in writeQuiet() }
        .onChange(of: quietStart) { _, _ in writeQuiet() }
        .onChange(of: quietEnd) { _, _ in writeQuiet() }
        .onChange(of: allowPage) { _, _ in writeQuiet() }
    }

    // MARK: What to send

    @ViewBuilder
    private func whatToSend(_ server: Server) -> some View {
        if model.hasSeveralOrgs {
            VStack(alignment: .leading, spacing: Brand.Space.inline) {
                Eyebrow("organizations")
                ForEach(model.orgs) { org in
                    Toggle(isOn: orgBinding(org)) {
                        Text(org.name).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                    }
                    .tint(Brand.Tone.hot)
                    .frame(minHeight: Brand.hitTarget)
                }
            }
            .padding(.vertical, Brand.Space.inline)
            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
        }

        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            Eyebrow("minimum severity")
            Picker("Minimum severity", selection: $prefs.minSeverity) {
                ForEach(MinSeverity.allCases) { Text($0.word).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("From the alert's severity label. An alert without one counts as a warning.")
                .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        }
        .padding(.vertical, Brand.Space.inline)
        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)

        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            Toggle(isOn: $quietOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet hours").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                    Text("Alerts still arrive, without a sound and without lighting the screen.")
                        .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                }
            }
            .tint(Brand.Tone.hot)
            .frame(minHeight: Brand.hitTarget)
            if quietOn {
                timeRow("From", $quietStart)
                timeRow("Until", $quietEnd)
                HStack {
                    Text("Time zone").font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                    Spacer()
                    Text(TimeZone.current.identifier).font(BrandFont.code).foregroundStyle(Brand.Tone.paper)
                }
                .frame(minHeight: Brand.hitTarget)
                Toggle(isOn: $allowPage) {
                    Text("Still ring for page").font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                }
                .tint(Brand.Tone.hot)
                .frame(minHeight: Brand.hitTarget)
            }
        }
        .padding(.vertical, Brand.Space.inline)
        .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)

        syncLine(server)
            .padding(.vertical, Brand.Space.inline)
            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
    }

    private func timeRow(_ label: String, _ date: Binding<Date>) -> some View {
        HStack {
            Text(label).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            Spacer()
            DatePicker(label, selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Brand.Tone.hot)
        }
        .frame(minHeight: Brand.hitTarget)
    }

    @ViewBuilder
    private func syncLine(_ server: Server) -> some View {
        if model.push.deviceToken == nil {
            Interlock(reason: "Allow notifications below first; there is no device to file these under")
        } else if server.relay == nil {
            Interlock(reason: "Give \(server.name) a relay under Settings › Servers to send these")
        } else if server.isAnonymous {
            Interlock(reason: "\(server.name) is read without signing in; push needs a Grafana login to file this phone under")
        } else {
            switch model.push.preferences(for: server.id) {
            case .none: ReadingLine(signal: .none, text: "Not handed to the relay yet; they go with the next registration.")
            case .pending: ReadingLine(signal: .wait, text: "Handing these to the relay.")
            case .pass(let at): ReadingLine(signal: .ok, text: "The relay has these as of \(at.formatted(date: .omitted, time: .standard)).")
            case .refuse(let why): ReadingLine(signal: .stop, text: why)
            }
        }
    }

    private func orgBinding(_ org: GrafanaOrg) -> Binding<Bool> {
        Binding(
            get: { prefs.orgs == nil || (prefs.orgs?.contains(org.orgId) ?? false) },
            set: { on in
                let every = model.orgs.map(\.orgId)
                var chosen = Set(prefs.orgs ?? every)
                if on { chosen.insert(org.orgId) } else { chosen.remove(org.orgId) }
                let kept = every.filter(chosen.contains)
                prefs.orgs = kept.count == every.count ? nil : kept
            }
        )
    }

    // MARK: Delivery

    @ViewBuilder
    private var delivery: some View {
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
        if let server {
            row("Relay") {
                if let relay = server.relay {
                    Text(relay.host ?? relay.absoluteString).font(BrandFont.code).foregroundStyle(Brand.Tone.paper).lineLimit(1)
                } else {
                    StateChip(word: "NONE", signal: .none)
                }
            }
            row("Registration") {
                switch model.push.registration(for: server.id) {
                case .none: StateChip(word: "NOT SENT", signal: .none)
                case .pending: StateChip(word: "PENDING", signal: .wait)
                case .pass(let at): StateChip(word: "PASS \(at.formatted(date: .omitted, time: .standard))", signal: .ok)
                case .refuse: StateChip(word: "REFUSE", signal: .stop)
                }
            }
            if let who = model.push.registeredAs[server.id] {
                row("Filed under") { Text(who).font(BrandFont.code).foregroundStyle(Brand.Tone.paper) }
            }
            if case .refuse(let why) = model.push.registration(for: server.id) {
                Text(why).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                    .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
            }
        }
        if model.push.deviceToken == nil {
            Interlock(reason: "No device token yet; allow notifications first")
                .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
        } else if let server, server.relay == nil {
            Interlock(reason: "Give \(server.name) a relay under Settings › Servers to register this phone")
                .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
        } else if let server {
            Button(registering ? "Registering…" : "Register this phone with \(server.relay?.host ?? "the relay")") {
                guard !registering else { return }
                registering = true
                Task { await model.registerPush(for: server); registering = false }
            }
            .buttonStyle(ThrowButtonStyle(primary: false))
            .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
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

    // MARK: State

    private func load() {
        guard let server else { return }
        let kept = model.notificationPrefs(for: server)
        prefs = kept
        if let quiet = kept.quiet {
            quietOn = true
            quietStart = Self.date(from: quiet.start) ?? quietStart
            quietEnd = Self.date(from: quiet.end) ?? quietEnd
            allowPage = quiet.allowPage
        }
        loaded = true
    }

    private func writeQuiet() {
        guard loaded else { return }
        let next: NotificationPrefs.Quiet? = quietOn
            ? NotificationPrefs.Quiet(start: Self.string(from: quietStart), end: Self.string(from: quietEnd), tz: TimeZone.current.identifier, allowPage: allowPage)
            : nil
        if next != prefs.quiet { prefs.quiet = next }
    }

    private static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }

    private static func string(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func date(from text: String) -> Date? {
        let halves = text.split(separator: ":")
        guard halves.count == 2, let hour = Int(halves[0]), let minute = Int(halves[1]) else { return nil }
        return time(hour, minute)
    }
}
