import SwiftUI

struct AlertDetailView: View {
    @Environment(AppModel.self) private var model
    let alert: GrafanaAlert
    @State private var showSilence = false
    @State private var latch: ThrowResult?

    /// The list's current reading of this alert, or the snapshot we were handed (a tapped push).
    private var live: GrafanaAlert { model.alerts.first { $0.id == alert.id } ?? alert }

    private var activeSilences: [Silence] {
        model.silences.filter { silence in
            silence.status.state == "active"
                && silence.matchers.allSatisfy { m in live.labels[m.name] == m.value }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Space.card) {
                header
                if let latch {
                    LatchView(result: latch) { self.latch = nil }
                }
                actions
                if let summary = live.summary, !summary.isEmpty {
                    Labelled("summary") {
                        Text(summary).font(BrandFont.body).foregroundStyle(Brand.Tone.paper)
                    }
                }
                Labelled("labels") { KeyValueRows(rows: live.visibleLabels) }
                let notes = live.annotations.filter { $0.key != "summary" }.sorted { $0.key < $1.key }
                if !notes.isEmpty {
                    Labelled("annotations") { KeyValueRows(rows: notes.map { ($0.key, $0.value) }) }
                }
                if !activeSilences.isEmpty {
                    Labelled("silenced") {
                        KeyValueRows(rows: activeSilences.map { s in
                            ("until \(s.endDate?.formatted(date: .abbreviated, time: .shortened) ?? s.endsAt)", "\(s.createdBy): \(s.comment)")
                        })
                    }
                }
            }
            .padding(Brand.Space.card)
        }
        .background(Brand.Tone.ink)
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSilence) {
            SilenceSheet(alert: live) { result in latch = result }
        }
        #if DEBUG
        .task {
            // Screenshot hook: BRAZIER_SHOT=silence shows the silence sheet over this alert.
            if ProcessInfo.processInfo.environment["BRAZIER_SHOT"] == "silence" {
                try? await Task.sleep(for: .seconds(1))
                showSilence = true
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            HStack(spacing: Brand.Space.inline) {
                StateChip(word: live.phase.word, signal: live.phase.signal)
                if let severity = live.labels["severity"] {
                    StateChip(word: severity, signal: severity == "page" ? .stop : .wait)
                }
                if !activeSilences.isEmpty {
                    StateChip(word: "SILENCED", signal: .wait)
                }
            }
            Text(live.name).font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
            HStack(spacing: Brand.Space.inline) {
                if let org = live.orgName { Eyebrow("\(org) ·") }
                Eyebrow(live.folder.isEmpty ? "no folder" : live.folder)
                if let since = live.activeDate {
                    Eyebrow("· since \(since.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Brand.Space.inline) {
            Button("Silence…") { showSilence = true }
                .buttonStyle(ThrowButtonStyle())
            if let server = model.selectedServer,
               let url = URL(string: "\(server.url.absoluteString)/alerting/list?search=\(live.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")\(live.orgId.map { "&orgId=\($0)" } ?? "")") {
                Link(destination: url) {
                    HStack { Text("Open in Grafana"); Image(systemName: "arrow.up.right") }
                }
                .buttonStyle(ThrowButtonStyle(primary: false))
            }
        }
    }
}
