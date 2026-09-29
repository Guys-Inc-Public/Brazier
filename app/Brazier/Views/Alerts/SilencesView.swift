import SwiftUI

/// Every silence on the mounted server, in the organizations on the screen: active ones first with the
/// control to end them, then pending, then what expired. Grafana keeps expired silences for a while.
struct SilencesView: View {
    @Environment(AppModel.self) private var model
    @State private var latch: ThrowResult?
    @State private var ending: String?

    private enum Group_: String, CaseIterable, Identifiable {
        case active, pending, expired
        var id: String { rawValue }
        var title: String {
            switch self {
            case .active: return "Active"
            case .pending: return "Starts later"
            case .expired: return "Expired"
            }
        }
        var signal: Signal {
            switch self {
            case .active: return .wait
            case .pending: return .none
            case .expired: return .ok
            }
        }
    }

    private func silences(in group: Group_) -> [Silence] {
        model.silences
            .filter { $0.status.state == group.rawValue }
            .sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
    }

    private var orgName: [Int: String] {
        Dictionary(uniqueKeysWithValues: model.orgs.map { ($0.orgId, $0.name) })
    }

    var body: some View {
        List {
            if let latch {
                LatchView(result: latch) { self.latch = nil }
                    .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
            }
            if model.silences.isEmpty {
                HStack(spacing: Brand.Space.label) {
                    Lamp(signal: .ok)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No silences").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                        Text("Nothing on this server is silenced. Silence an alert from its own page.")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                    }
                }
                .padding(.vertical, Brand.Space.label)
                .listRowBackground(Brand.Tone.ink).listRowSeparator(.hidden)
            }
            ForEach(Group_.allCases) { group in
                let rows = silences(in: group)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { silence in
                            row(silence, group: group)
                                .listRowBackground(Brand.Tone.ink)
                                .listRowSeparatorTint(Brand.Tone.line)
                        }
                    } header: {
                        HStack {
                            StateChip(word: group.rawValue.uppercased(), signal: group.signal)
                            Text(group.title).font(BrandFont.label).foregroundStyle(Brand.Tone.paper)
                            Spacer()
                            Text("\(rows.count)").font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                        }
                        .textCase(nil)
                        .padding(.vertical, Brand.Space.hairline)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.Tone.ink)
        .navigationTitle("Silences")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private func row(_ silence: Silence, group: Group_) -> some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            HStack(alignment: .top, spacing: Brand.Space.label) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(silence.alertName ?? "Silence").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                    Text(silence.matcherLine).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(2)
                    HStack(spacing: Brand.Space.inline) {
                        if model.showsOrgChips, let org = silence.orgId, let name = orgName[org] {
                            StateChip(word: AlertRow.chipWord(name), signal: .none).fixedSize()
                        }
                        Text(whenLine(silence, group: group)).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                    }
                    if !silence.comment.isEmpty {
                        Text("\(silence.createdBy.isEmpty ? "" : "\(silence.createdBy): ")\(silence.comment)")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.paper).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if group != .expired, model.selectedServer?.isAnonymous != true {
                if ending == silence.id {
                    HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("ending") }.frame(minHeight: Brand.hitTarget)
                } else {
                    Button(group == .active ? "End now" : "Cancel") { end(silence) }
                        .buttonStyle(MomentaryButtonStyle())
                        .padding(.leading, -Brand.Space.inline)
                }
            }
        }
        .padding(.vertical, Brand.Space.hairline)
        .opacity(group == .expired ? 0.6 : 1)
    }

    private func whenLine(_ silence: Silence, group: Group_) -> String {
        let until = silence.endDate?.formatted(date: .abbreviated, time: .shortened) ?? silence.endsAt
        switch group {
        case .active: return "until \(until)"
        case .pending: return "from \(silence.startDate?.formatted(date: .abbreviated, time: .shortened) ?? silence.startsAt) until \(until)"
        case .expired: return "ended \(until)"
        }
    }

    private func end(_ silence: Silence) {
        ending = silence.id
        Task {
            latch = await model.expire(silence)
            ending = nil
        }
    }
}
