import SwiftUI

/// Step 3: the permission. The relay, if any, was entered with the address; here the phone is told what
/// push needs and asked once. Skipping is always allowed.
struct NotificationsStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var draft: SetupDraft
    let back: () -> Void
    /// Called with whether iOS was asked for permission on the way out.
    let next: (Bool) -> Void

    @State private var asking = false

    var body: some View {
        StepPage(title: "Alerts on the lock screen", lead: "Grafana cannot push to phones by itself. A small relay, run by whoever runs your Grafana, receives its webhook and hands each alert to Apple.") {
            if let relay = draft.relayURL {
                ReadingLine(signal: .ok, text: "Relay \(relay.host ?? relay.absoluteString) · alerts will be handed to this phone")
                Text("Continue asks iOS for permission to show notifications, then registers this phone with the relay under your Grafana login.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            } else {
                VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                    Eyebrow("no relay")
                    Text("Push needs a relay, and none was given. Alerts still read from Grafana whenever the app is open. Go back to enter your admin's relay address, or add one later under Settings.")
                        .font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                }
                Text("Continue still asks iOS for permission, so a relay added later works at once.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        } footer: {
            StepButtons(back: back, primary: "Continue", busy: asking, action: allowAndContinue,
                        secondary: ("Skip for now", { next(false) }))
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
