import SwiftUI

/// Step 1: the Grafana address, checked against /api/health, and the relay if the admin gave one.
/// A tested relay can say how this Grafana signs in, which shapes the next step.
struct ServerStep: View {
    @Bindable var draft: SetupDraft
    let back: (() -> Void)?
    let next: () -> Void

    @State private var checking = false
    @State private var testing = false
    @State private var problem: String?
    @State private var relayFault: String?
    @FocusState private var focused: Field?

    enum Field { case address, relay }

    private var isChecked: Bool {
        draft.health?.isOK == true && draft.checkedText == draft.urlText && draft.url != nil
    }

    private var relayTyped: Bool { !draft.relayText.trimmingCharacters(in: .whitespaces).isEmpty }

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
                    .onSubmit { if isChecked { focused = .relay } else { check() } }
                if checking {
                    HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("checking \(draft.url?.host ?? "")") }
                        .frame(minHeight: Brand.hitTarget)
                } else if let problem {
                    ReadingLine(signal: .stop, text: problem)
                } else if isChecked, case .ok(let version, let database) = draft.health {
                    ReadingLine(signal: database == "ok" ? .ok : .wait, text: "Grafana \(version) · reachable")
                }
            }
            Labelled("relay address · optional") {
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
                Text("Your Grafana admin may have given you one. It delivers alerts to this phone and can tell Brazier how you sign in.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
            VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                Eyebrow("good to know")
                Text("Grafana behind a VPN or tunnel works when this phone can reach it. A self-signed certificate needs its profile installed and trusted on the phone first. Plain http is allowed for localhost only.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        } footer: {
            StepButtons(back: back, primary: primary, blocker: blocker, busy: checking || testing) {
                if !isChecked { check() }
                else if relayTyped, !draft.relayTested { testRelay(thenContinue: true) }
                else { next() }
            }
        }
        .onAppear { if draft.urlText.isEmpty { focused = .address } }
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
