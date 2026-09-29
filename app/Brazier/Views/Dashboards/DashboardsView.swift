import SwiftUI

/// Milestone 3 stub: the search list, and each dashboard in a web view. Kiosk mode, JWT on the first load.
struct DashboardsView: View {
    @Environment(AppModel.self) private var model
    @State private var hits: [SearchHit] = []
    @State private var query = ""
    @State private var reading = false
    @State private var fault: String?
    @State private var asOf: Date?

    var body: some View {
        NavigationStack {
            Group {
                if model.selectedServer == nil {
                    BlankBay(title: "No server", text: "Add a Grafana under Settings › Servers.")
                } else if !model.signedIn {
                    BlankBay(title: "Not signed in", text: "Sign in on the Alerts tab or under Settings › Servers.")
                } else if let fault, hits.isEmpty {
                    FaultCard(fault: Fault(at: asOf ?? Date(), call: "GET /api/search", reason: fault)) { Task { await load() } }
                        .padding(Brand.Space.card)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if reading && hits.isEmpty {
                    WarmingBay(name: model.selectedServer?.name ?? "")
                } else {
                    list
                }
            }
            .background(Brand.Tone.ink)
            .navigationTitle("Dashboards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { HeaderMark() }
                ToolbarItem(placement: .topBarTrailing) { ServerMenu() }
            }
            .navigationDestination(for: SearchHit.self) { DashboardWebView(hit: $0) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        AsOfStamp(asOf: asOf, failedAt: fault == nil ? nil : Date())
                        Spacer()
                        Eyebrow("\(hits.count) dashboards")
                    }
                    .padding(.horizontal, Brand.Space.card).padding(.vertical, Brand.Space.inline)
                }
                .background(Brand.Tone.ink)
            }
        }
        .task(id: model.selectedServerID) { await load() }
        .task(id: model.signedIn) { if model.signedIn && hits.isEmpty { await load() } }
    }

    private var list: some View {
        List(filtered) { hit in
            NavigationLink(value: hit) {
                HStack(spacing: Brand.Space.label) {
                    Image(systemName: hit.isStarred == true ? "star.fill" : "rectangle.grid.2x2")
                        .foregroundStyle(hit.isStarred == true ? Brand.Tone.hot : Brand.Tone.muted)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title).font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                        HStack(spacing: Brand.Space.inline) {
                            Text(hit.folderTitle ?? "General").font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                            if !hit.tags.isEmpty {
                                Text(hit.tags.joined(separator: " · ")).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(minHeight: Brand.hitTarget)
            }
            .listRowBackground(Brand.Tone.ink)
            .listRowSeparatorTint(Brand.Tone.line)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Dashboard, folder, tag")
        .refreshable { await load() }
    }

    private var filtered: [SearchHit] {
        let q = query.lowercased()
        guard !q.isEmpty else { return hits }
        return hits.filter {
            $0.title.lowercased().contains(q) || ($0.folderTitle?.lowercased().contains(q) ?? false) || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private func load() async {
        guard let server = model.selectedServer, model.signedIn else { return }
        reading = true
        defer { reading = false }
        do {
            hits = try await model.client(for: server).search("").sorted { ($0.isStarred == true ? 0 : 1, $0.title) < ($1.isStarred == true ? 0 : 1, $1.title) }
            asOf = Date()
            fault = nil
        } catch {
            fault = error.localizedDescription
            model.record("GET /api/search", error)
        }
    }
}
