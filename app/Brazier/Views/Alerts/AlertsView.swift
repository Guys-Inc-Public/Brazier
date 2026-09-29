import SwiftUI

/// The rack of alert instances on the mounted server: firing, pending, faults, normal.
struct AlertsView: View {
    @Environment(AppModel.self) private var model
    /// On a wide screen the rack is a column and the chosen alert opens beside it; on a phone it pushes.
    var selection: Binding<GrafanaAlert?>?
    @State private var query = ""
    @State private var path = NavigationPath()

    /// The silences screen, pushed from the row above the rack.
    struct SilencesRoute: Hashable {}

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
        NavigationStack(path: $path) {
            content
                .background(Brand.Tone.ink)
                .navigationTitle("Alerts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if selection == nil { ToolbarItem(placement: .principal) { HeaderMark() } }
                    ToolbarItem(placement: .topBarTrailing) { ServerMenu() }
                }
                .navigationDestination(for: GrafanaAlert.self) { AlertDetailView(alert: $0) }
                .navigationDestination(for: SilencesRoute.self) { _ in SilencesView() }
                .navigationDestination(item: selection == nil ? $model.pendingAlert : .constant(nil)) { AlertDetailView(alert: $0) }
                .safeAreaInset(edge: .bottom, spacing: 0) { stampBar }
        }
        #if DEBUG
        .onChange(of: model.bay) { _, bay in
            // Screenshot hooks: BRAZIER_SHOT=silence opens the first firing alert (its silence sheet follows);
            // BRAZIER_SHOT=silences opens the silences list.
            guard bay == .mounted, path.isEmpty else { return }
            switch ProcessInfo.processInfo.environment["BRAZIER_SHOT"] ?? "" {
            case "silence":
                guard selection?.wrappedValue == nil,
                      let first = model.alerts.filter({ $0.phase == .firing }).sorted(by: { $0.name < $1.name }).first else { return }
                if let selection { selection.wrappedValue = first } else { path.append(first) }
            case "silences":
                path.append(SilencesRoute())
            default:
                break
            }
        }
        #endif
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

    @ViewBuilder private var list: some View {
        if let selection {
            List(selection: selection) { rows }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Alert, label, host")
                .refreshable { await model.refresh() }
        } else {
            List { rows }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Alert, label, host")
                .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder private var rows: some View {
            if !model.unkeptFaults.isEmpty {
                FaultRail()
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: Brand.Space.inline, leading: Brand.Space.card, bottom: Brand.Space.inline, trailing: Brand.Space.card))
            }
            if query.isEmpty {
                NavigationLink(value: SilencesRoute()) { silencesRow }
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparatorTint(Brand.Tone.line)
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
                                if let selection {
                                    AlertRow(alert: alert, showOrg: model.showsOrgChips, silenced: silencedIDs.contains(alert.id))
                                        .tag(alert)
                                        .listRowBackground(selection.wrappedValue?.id == alert.id ? Brand.Tone.raise : Brand.Tone.ink)
                                        .listRowSeparatorTint(Brand.Tone.line)
                                } else {
                                    NavigationLink(value: alert) { AlertRow(alert: alert, showOrg: model.showsOrgChips, silenced: silencedIDs.contains(alert.id)) }
                                        .listRowBackground(Brand.Tone.ink)
                                        .listRowSeparatorTint(Brand.Tone.line)
                                }
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

    /// Silences on the mounted server, as one row: how many are active now, and the way to them.
    private var silencesRow: some View {
        let active = model.silences.filter(\.isActive).count
        return HStack(spacing: Brand.Space.label) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active > 0 ? Brand.Tone.hot : Brand.Tone.muted)
                .frame(width: 20)
            Text("Silences").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
            Spacer()
            Text(active == 0 ? "none active" : "\(active) active").font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
        }
        .frame(minHeight: Brand.hitTarget)
    }

    /// The instances an active silence covers, so their rows can say so.
    private var silencedIDs: Set<String> {
        let active = model.silences.filter(\.isActive)
        guard !active.isEmpty else { return [] }
        var ids = Set<String>()
        for alert in model.alerts where active.contains(where: { $0.covers(alert) }) {
            ids.insert(alert.id)
        }
        return ids
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
