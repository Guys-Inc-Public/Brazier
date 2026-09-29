import SwiftUI

/// Step 1: the address, checked against /api/health before anything else is asked.
struct ServerStep: View {
    @Bindable var draft: SetupDraft
    let back: (() -> Void)?
    let next: () -> Void

    @State private var checking = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var isChecked: Bool {
        draft.health?.isOK == true && draft.checkedText == draft.urlText && draft.url != nil
    }

    private var blocker: String? {
        if draft.urlText.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the address to check it" }
        return nil
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
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { if isChecked { next() } else { check() } }
            }
            if checking {
                HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("checking \(draft.url?.host ?? "")") }
                    .frame(minHeight: Brand.hitTarget)
            } else if let problem {
                ReadingLine(signal: .stop, text: problem)
            } else if isChecked, case .ok(let version, let database) = draft.health {
                ReadingLine(signal: database == "ok" ? .ok : .wait, text: "Grafana \(version) · reachable")
            }
            VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                Eyebrow("good to know")
                Text("Grafana behind a VPN or tunnel works when this phone can reach it. A self-signed certificate needs its profile installed and trusted on the phone first. Plain http is allowed for localhost only.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        } footer: {
            StepButtons(back: back, primary: isChecked ? "Continue" : "Check address", blocker: blocker, busy: checking) {
                if isChecked { next() } else { check() }
            }
        }
        .onAppear { focused = draft.urlText.isEmpty }
    }

    private func check() {
        focused = false
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
}
