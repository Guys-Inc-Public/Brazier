import SwiftUI

/// The rack of alert instances on the mounted server: firing, pending, faults, normal.
struct AlertsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private enum Row: Identifiable {
        /// A folder heading: its key (organization and folder) and the words to show.
        case folder(String, String)
        case alert(GrafanaAlert)

        var id: String {
            switch self {
            case .folder(let key, _): return "folder:\(key)"
            case .alert(let alert): return "alert:\(alert.id)"
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            content
                .background(Brand.Tone.ink)
                .navigationTitle("Alerts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { HeaderMark() }
                    ToolbarItem(placement: .topBarTrailing) { ServerMenu() }
                }
                .navigationDestination(for: GrafanaAlert.self) { AlertDetailView(alert: $0) }
                .navigationDestination(item: $model.pendingAlert) { AlertDetailView(alert: $0) }
                .safeAreaInset(edge: .bottom, spacing: 0) { stampBar }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.bay {
        case .blank:
            BlankBay(title: "No server", text: "Add a Grafana under Settings › Servers.")
        case .warming:
            WarmingBay(name: model.selectedServer?.name ?? "")
        case .faulted(let reason):
            FaultedBay(reason: reason)
        case .mounted:
            list
        }
    }

    private var list: some View {
        List {
            if !model.unkeptFaults.isEmpty {
                FaultRail()
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: Brand.Space.inline, leading: Brand.Space.card, bottom: Brand.Space.inline, trailing: Brand.Space.card))
            }
            if filtered.isEmpty {
                emptyReading
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparator(.hidden)
            }
            ForEach(AlertPhase.allCases, id: \.self) { phase in
                let rows = rows(for: phase)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { row in
                            switch row {
                            case .folder(_, let title):
                                Eyebrow(title)
                                    .listRowBackground(Brand.Tone.ink)
                                    .listRowSeparator(.hidden)
                                    .padding(.top, Brand.Space.inline)
                            case .alert(let alert):
                                NavigationLink(value: alert) { AlertRow(alert: alert, showOrg: model.showsOrgChips) }
                                    .listRowBackground(Brand.Tone.ink)
                                    .listRowSeparatorTint(Brand.Tone.line)
                            }
                        }
                    } header: {
                        HStack {
                            StateChip(word: phase.word, signal: phase.signal)
                            Text(phase.title).font(BrandFont.label).foregroundStyle(Brand.Tone.paper)
                            Spacer()
                            Text("\(count(for: phase))").font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                        }
                        .textCase(nil)
                        .padding(.vertical, Brand.Space.hairline)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Alert, label, host")
        .refreshable { await model.refresh() }
    }

    private var emptyReading: some View {
        HStack(spacing: Brand.Space.label) {
            Lamp(signal: query.isEmpty ? .ok : .none)
            VStack(alignment: .leading, spacing: 2) {
                Text(query.isEmpty ? "No alert instances" : "Nothing matches").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                Text(query.isEmpty ? "The server reports no instances of any rule." : "No alert, label or host contains “\(query)”.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        }
        .padding(.vertical, Brand.Space.label)
    }

    private var stampBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                AsOfStamp(asOf: model.asOf, failedAt: model.lastFailure)
                Spacer()
                Eyebrow("\(count(for: .firing)) firing · \(model.alerts.count) instances")
            }
            .padding(.horizontal, Brand.Space.card)
            .padding(.vertical, Brand.Space.inline)
        }
        .background(Brand.Tone.ink)
    }

    // MARK: Rows

    private var filtered: [GrafanaAlert] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.alerts }
        return model.alerts.filter { alert in
            alert.name.lowercased().contains(q)
                || (alert.summary?.lowercased().contains(q) ?? false)
                || (alert.orgName?.lowercased().contains(q) ?? false)
                || alert.labels.values.contains { $0.lowercased().contains(q) }
        }
    }

    private func count(for phase: AlertPhase) -> Int {
        filtered.filter { $0.phase == phase }.count
    }

    /// Within a phase: by organization, then folder, then rule, then place. A folder heading names its
    /// organization too when more than one is on the screen, since two organizations may share a folder name.
    private func rows(for phase: AlertPhase) -> [Row] {
        let alerts = filtered
            .filter { $0.phase == phase }
            .sorted { ($0.orgName ?? "", $0.folder, $0.name, $0.placeLine) < ($1.orgName ?? "", $1.folder, $1.name, $1.placeLine) }
        var rows: [Row] = []
        var group: String?
        for alert in alerts {
            let key = "\(alert.orgId ?? 0)/\(alert.folder)"
            if key != group {
                group = key
                let folder = alert.folder.isEmpty ? "no folder" : alert.folder
                let title = model.showsOrgChips ? [alert.orgName, folder].compactMap { $0 }.joined(separator: " · ") : folder
                rows.append(.folder(key, title))
            }
            rows.append(.alert(alert))
        }
        return rows
    }
}
