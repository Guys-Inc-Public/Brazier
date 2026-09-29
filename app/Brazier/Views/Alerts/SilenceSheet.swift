import SwiftUI

/// A throw: writes a silence to the server and latches PASS or REFUSE until acknowledged.
struct SilenceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let alert: GrafanaAlert
    let onResult: (ThrowResult) -> Void

    @State private var duration: SilenceDuration = .h1
    @State private var comment = ""
    @State private var inFlight = false
    @State private var result: ThrowResult?

    private var matchers: [Matcher] { SilenceBuilder.matchers(for: alert.labels) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Space.card) {
                    VStack(alignment: .leading, spacing: Brand.Space.inline) {
                        Eyebrow("silence")
                        Text(alert.name).font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
                        Text("Grafana stops notifying for this instance until the silence ends. The rule keeps evaluating.")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                    }
                    Labelled("for") {
                        Picker("Duration", selection: $duration) {
                            ForEach(SilenceDuration.allCases) { Text($0.word).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Labelled("comment") {
                        TextField("Silenced from Brazier", text: $comment)
                            .fieldChrome()
                            .autocorrectionDisabled()
                    }
                    Labelled("matchers") {
                        KeyValueRows(rows: matchers.map { ($0.name, $0.value) })
                    }
                    if let result {
                        LatchView(result: result) { dismiss() }
                    } else if inFlight {
                        HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("writing") }
                            .frame(minHeight: Brand.hitTarget)
                    } else {
                        Button("Silence for \(duration.word)") {
                            inFlight = true
                            Task {
                                let outcome = await model.silence(alert: alert, duration: duration, comment: comment)
                                result = outcome
                                inFlight = false
                                onResult(outcome)
                            }
                        }
                        .buttonStyle(ThrowButtonStyle())
                    }
                }
                .padding(Brand.Space.card)
            }
            .background(Brand.Tone.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A plain toolbar button: the system draws the capsule, so the word is never cut.
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .font(BrandFont.label)
                        .tint(Brand.Tone.hot)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Brand.Tone.ink)
    }
}
