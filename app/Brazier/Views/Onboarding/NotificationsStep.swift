import SwiftUI

/// Step 3: the relay, if there is one, and the permission. Skipping is always allowed.
struct NotificationsStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var draft: SetupDraft
    let back: () -> Void
    /// Called with whether iOS was asked for permission on the way out.
    let next: (Bool) -> Void

    @State private var testing = false
    @State private var asking = false
    @State private var relayFault: String?

    private var relayTyped: Bool { !draft.relayText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        StepPage(title: "Alerts on the lock screen", lead: "Grafana cannot push to phones by itself. A small relay, run by whoever runs your Grafana, receives its webhook and hands each alert to Apple.") {
            Labelled("relay address · optional") {
                HStack(spacing: Brand.Space.inline) {
                    TextField("https://relay.example.com", text: $draft.relayText)
                        .fieldChrome()
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(test)
                    if testing {
                        MeterBridge().frame(width: 60)
                    } else {
                        Button("Test", action: test)
                            .buttonStyle(MomentaryButtonStyle())
                            .disabled(!relayTyped)
                            .opacity(relayTyped ? 1 : 0.4)
                    }
                }
                if let health = draft.relayHealth, draft.testedRelayText == draft.relayText {
                    ReadingLine(signal: health.ok ? .ok : .wait,
                                text: "Relay \(health.version ?? "") · \(health.ok ? "ok" : "not ok")\(health.apns == false ? " · push key not set yet" : "")")
                } else if let relayFault, draft.testedRelayText == draft.relayText {
                    ReadingLine(signal: .stop, text: relayFault)
                }
            }
            VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                Eyebrow("no relay?")
                Text("Skip this. Alerts still read from Grafana whenever the app is open, and a relay can be added later under Settings. The relay is open source; your admin can run one in a few minutes.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
            Text("Continue asks iOS for permission to show notifications.")
                .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        } footer: {
            StepButtons(back: back, primary: "Continue", blocker: blocker, busy: asking || testing, action: allowAndContinue,
                        secondary: ("Skip for now", { next(false) }))
        }
    }

    private var blocker: String? {
        guard relayTyped else { return nil }
        if draft.relayURL == nil { return "That relay address does not parse" }
        return nil
    }

    private func test() {
        guard let url = draft.relayURL else {
            relayFault = "That relay address does not parse; it needs https://"
            draft.testedRelayText = draft.relayText
            return
        }
        testing = true
        Task {
            do {
                draft.relayHealth = try await RelayClient(baseURL: url).health()
                relayFault = nil
            } catch {
                draft.relayHealth = nil
                relayFault = error.localizedDescription
            }
            draft.testedRelayText = draft.relayText
            testing = false
        }
    }

    private func allowAndContinue() {
        asking = true
        Task {
            draft.notificationsGranted = await model.push.requestPermission()
            asking = false
            next(true)
        }
    }
}
