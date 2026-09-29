import SwiftUI

/// The cover: the Curl, the name, one sentence, one throw.
struct WelcomeStep: View {
    let start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: Brand.Space.card) {
                Image("Mark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Brazier")
                    .font(BrandFont.display)
                    .tracking(-1.2)
                    .foregroundStyle(Brand.Tone.paper)
                Text("Alerts from your own Grafana, on your phone.")
                    .font(BrandFont.lead)
                    .foregroundStyle(Brand.Tone.paper)
                Text("Real push for firing and resolved alerts, silences from the lock screen, and your dashboards. Nothing leaves your Grafana but what you ask for.")
                    .font(BrandFont.body)
                    .foregroundStyle(Brand.Tone.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.Space.card)
            Spacer()
            Hairline()
            VStack(spacing: Brand.Space.inline) {
                Button("Get started", action: start).buttonStyle(ThrowButtonStyle())
                Text("Open source, MIT. Not affiliated with Grafana Labs.")
                    .font(BrandFont.meta)
                    .foregroundStyle(Brand.Tone.muted)
            }
            .padding(.horizontal, Brand.Space.card)
            .padding(.vertical, Brand.Space.label)
        }
    }
}

/// The last plate: what was set up, and the way in.
struct DoneStep: View {
    @Environment(AppModel.self) private var model
    let draft: SetupDraft
    let onFinished: () -> Void

    private var signInLine: String {
        switch draft.method {
        case .oidc: return "\(draft.providerName ?? "Provider") single sign-on"
        case .session: return "Grafana's page"
        case .token: return "Service account token"
        case .anonymous: return "Without signing in"
        case nil: return ""
        }
    }

    private var pushLine: String {
        guard draft.relayURL != nil else { return "not set up; add a relay under Settings › Servers" }
        if draft.method == .anonymous { return "relay set; sign in to get pushes" }
        switch draft.notificationsGranted {
        case true: return "relay set, notifications allowed"
        case false: return "relay set, notifications refused; allow them in iOS Settings"
        default: return "relay set, notifications skipped"
        }
    }

    var body: some View {
        StepPage(title: "You're set", lead: "\(draft.name) is mounted. Alerts read from it now; pushes arrive when the relay hands one over.") {
            KeyValueRows(rows: [
                ("Server", draft.url?.absoluteString ?? draft.name),
                ("Sign-in", signInLine),
                ("As", draft.user?.login ?? (draft.method == .anonymous ? "anonymous" : "")),
                ("Push", pushLine),
            ])
            Text("Add more servers any time under Settings › Servers.")
                .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        } footer: {
            StepButtons(primary: "Open alerts") { onFinished() }
        }
    }
}
