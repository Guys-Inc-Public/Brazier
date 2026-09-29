import SwiftUI

/// Step 1: the Grafana address, checked against /api/health. A reachable reading, gate in front or not,
/// then reads how the Grafana signs in and asks the admin's signpost for the relay and the sign-in, so
/// most people type one thing. A relay can still be typed by hand when nothing is published.
struct ServerStep: View {
    @Bindable var draft: SetupDraft
    let back: (() -> Void)?
    let next: () -> Void

    @State private var checking = false
    @State private var testing = false
    @State private var problem: String?
    @State private var relayFault: String?
    @State private var relayOpen = false
    @FocusState private var focused: Field?

    enum Field { case address, relay }

    private var isChecked: Bool {
        draft.health?.isReachable == true && draft.checkedText == draft.urlText && draft.url != nil
    }

    private var looking: Bool { draft.discovery == .looking && draft.discoveredText == draft.checkedText }

    private var relayTyped: Bool { !draft.relayText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The relay the signpost named, when the field still holds it.
    private var foundRelay: URL? {
        guard let relay = draft.discovered?.relayURL, draft.relayText == relay.absoluteString else { return nil }
        return relay
    }

    /// Nothing published, or the published relay is not answering: offer the field.
    private var offerRelayField: Bool {
        guard isChecked, !looking, draft.discoveredText == draft.checkedText else { return false }
        if draft.discovery == .nothing { return true }
        return draft.discovered?.relayURL == nil || (foundRelay != nil && !draft.relayTested) || relayOpen
    }

    private var blocker: String? {
        if draft.urlText.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the address to check it" }
        if relayTyped, draft.relayURL == nil { return "That relay address does not parse; it needs https://" }
        return nil
    }

    private var primary: String {
        if !isChecked { return "Check address" }
        if relayTyped, !draft.relayTested { return "Test relay and continue" }
        return "Continue"
    }

    var body: some View {
        StepPage(title: "Where is your Grafana?", lead: "The address you open in a browser. Brazier reads its API and shows its pages; it never goes anywhere else.") {
            Labelled("your grafana's address") {
                TextField("https://grafana.example.com", text: $draft.urlText)
                    .fieldChrome()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .address)
                    .submitLabel(.go)
                    .onSubmit { if !isChecked { check() } }
                if checking {
                    HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("checking \(draft.url?.host ?? "")") }
                        .frame(minHeight: Brand.hitTarget)
                } else if let problem {
                    ReadingLine(signal: .stop, text: problem)
                } else if isChecked, case .ok(let version, let database) = draft.health {
                    ReadingLine(signal: database == "ok" ? .ok : .wait, text: "Grafana \(version) · reachable")
                    discoveryLines
                } else if isChecked, case .fronted = draft.health {
                    ReadingLine(signal: .wait, text: "Something in front asks you to sign in first · that works on the next step")
                    discoveryLines
                }
            }
            if offerRelayField {
                MethodCard(title: "Have a relay address from your admin?", text: "It delivers alerts to this phone and can tell Brazier how you sign in. Without one, Brazier still shows everything; it just cannot buzz.", open: $relayOpen) {
                    relayField
                }
            }
            VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                Eyebrow("good to know")
                Text("Grafana behind a VPN or tunnel works when this phone can reach it. A self-signed certificate needs its profile installed and trusted on the phone first. Plain http is allowed for localhost only.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        } footer: {
            StepButtons(back: back, primary: primary, blocker: blocker, busy: checking || testing || looking) {
                if !isChecked { check() }
                else if relayTyped, !draft.relayTested { testRelay(thenContinue: true) }
                else { next() }
            }
        }
        .onAppear { if draft.urlText.isEmpty { focused = .address } }
    }

    /// What the signpost said, line by line as it resolves.
    @ViewBuilder private var discoveryLines: some View {
        if draft.discoveredText == draft.checkedText {
            switch draft.discovery {
            case .looking:
                HStack(spacing: Brand.Space.label) {
                    MeterBridge()
                    Text("Looking for your admin's settings…").font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                }
            case .found(let found):
                if let relay = found.relayURL { relayLine(relay) }
                if let signIn = draft.published { ReadingLine(signal: .ok, text: "Signs in with \(signIn.displayName)") }
            case .nothing:
                ReadingLine(signal: .none, text: "No relay published for this Grafana")
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func relayLine(_ relay: URL) -> some View {
        let host = relay.host ?? relay.absoluteString
        if foundRelay != nil, draft.relayTested, let health = draft.relayHealth {
            let reading = [health.version, "ok"].compactMap { $0 }.joined(separator: " ")
            ReadingLine(signal: .ok, text: "Relay found · \(host) · \(reading)\(health.apns == false ? " · push key not set yet" : "")")
        } else if foundRelay != nil {
            ReadingLine(signal: .stop, text: "Relay found · \(host) · not answering")
        } else {
            ReadingLine(signal: .none, text: "Relay found · \(host) · replaced below")
        }
    }

    private var relayField: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            HStack(spacing: Brand.Space.inline) {
                TextField("https://relay.example.com", text: $draft.relayText)
                    .fieldChrome()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .relay)
                    .submitLabel(.go)
                    .onSubmit { testRelay(thenContinue: false) }
                if testing {
                    MeterBridge().frame(width: 60)
                } else {
                    Button("Test") { testRelay(thenContinue: false) }
                        .buttonStyle(MomentaryButtonStyle())
                        .disabled(!relayTyped)
                        .opacity(relayTyped ? 1 : 0.4)
                }
            }
            if draft.relayTested, let health = draft.relayHealth {
                ReadingLine(signal: .ok, text: "Relay \(health.version ?? "") · ok\(health.apns == false ? " · push key not set yet" : "")")
                if let signIn = draft.published {
                    ReadingLine(signal: .ok, text: "Signs in with \(signIn.displayName)")
                }
            } else if let relayFault, draft.testedRelayText == draft.relayText {
                ReadingLine(signal: .stop, text: relayFault)
            }
        }
    }

    private func check() {
        focused = nil
        switch ServerAddress.normalise(draft.urlText) {
        case .problem(let why):
            problem = why
        case .url(let url):
            problem = nil
            checking = true
            if draft.url != url { draft.resetVerification() }
            Task {
                let outcome = await ServerProbe.health(url)
                draft.url = url
                draft.health = outcome
                draft.checkedText = draft.urlText
                if case .failed(let why) = outcome { problem = why }
                checking = false
                await draft.discover()
            }
        }
    }

    /// Health first; a healthy relay is then asked for its directory, which may name the sign-in.
    private func testRelay(thenContinue: Bool) {
        focused = nil
        guard let url = draft.relayURL else {
            relayFault = "That relay address does not parse; it needs https://"
            draft.testedRelayText = draft.relayText
            return
        }
        testing = true
        Task {
            let client = RelayClient(baseURL: url)
            do {
                let health = try await client.health()
                draft.relayHealth = health
                draft.relayDirectory = try? await client.directory()
                relayFault = health.ok ? nil : "The relay answered, but reports itself not ok"
            } catch {
                draft.relayHealth = nil
                draft.relayDirectory = nil
                relayFault = error.localizedDescription
            }
            draft.testedRelayText = draft.relayText
            testing = false
            if thenContinue, draft.relayTested { next() }
        }
    }
}
