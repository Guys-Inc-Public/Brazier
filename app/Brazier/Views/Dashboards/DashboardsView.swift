import SwiftUI

/// The search list, grouped by organization when more than one is on the screen; each dashboard opens
/// in a web view with the session carried over.
struct DashboardsView: View {
    @Environment(AppModel.self) private var model
    @State private var hits: [SearchHit] = []
    @State private var query = ""
    @State private var reading = false
    @State private var fault: String?
    @State private var asOf: Date?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
        .task(id: loadKey) { await load() }
    }

    /// Reads again when the server, the sign-in or the organizations on the screen change; the
    /// organization list arrives a moment after the sign-in, so the key follows it.
    private var loadKey: String {
        "\(model.selectedServerID?.uuidString ?? "")|\(model.signedIn)|\(model.selectedOrgs.map { String($0.orgId) }.joined(separator: ","))"
    }

    private var list: some View {
        List {
            if filtered.isEmpty {
                emptyReading
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparator(.hidden)
            }
            ForEach(grouped, id: \.key) { group in
                Section {
                    ForEach(group.hits) { hit in row(hit) }
                } header: {
                    if let org = group.org {
                        Eyebrow(org).textCase(nil).padding(.vertical, Brand.Space.hairline)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Dashboard, folder, tag")
        .refreshable { await load() }
    }

    private func row(_ hit: SearchHit) -> some View {
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

    private var emptyReading: some View {
        HStack(spacing: Brand.Space.label) {
            Lamp(signal: query.isEmpty ? .ok : .none)
            VStack(alignment: .leading, spacing: 2) {
                Text(query.isEmpty ? "No dashboards" : "Nothing matches").font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                Text(query.isEmpty ? "The search found no dashboards you can see." : "No dashboard, folder or tag contains “\(query)”.")
                    .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            }
        }
        .padding(.vertical, Brand.Space.label)
    }

    private var filtered: [SearchHit] {
        let q = query.lowercased()
        guard !q.isEmpty else { return hits }
        return hits.filter {
            $0.title.lowercased().contains(q) || ($0.folderTitle?.lowercased().contains(q) ?? false) || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private struct Group_: Identifiable {
        let key: String
        let org: String?
        let hits: [SearchHit]
        var id: String { key }
    }

    /// One section per organization on the screen, in the server's order; one unnamed section otherwise.
    private var grouped: [Group_] {
        let list = filtered
        guard model.selectedOrgs.count > 1 else { return [Group_(key: "all", org: nil, hits: list)] }
        return model.selectedOrgs.compactMap { org in
            let mine = list.filter { $0.orgId == org.orgId }
            return mine.isEmpty ? nil : Group_(key: String(org.orgId), org: org.name, hits: mine)
        }
    }

    private func load() async {
        guard let server = model.selectedServer, model.signedIn else { return }
        reading = true
        defer { reading = false }
        let client = model.client(for: server)
        let targets = model.selectedOrgs
        do {
            var found: [SearchHit]
            if targets.isEmpty {
                found = try await client.search("")
            } else {
                found = try await Self.search(client, orgs: targets)
            }
            found.sort { ($0.isStarred == true ? 0 : 1, $0.title) < ($1.isStarred == true ? 0 : 1, $1.title) }
            hits = found
            asOf = Date()
            fault = nil
            #if DEBUG
            // Screenshot hook: BRAZIER_SHOT=dashboard opens the first dashboard, so the session carry-over is seen.
            if ProcessInfo.processInfo.environment["BRAZIER_SHOT"] == "dashboard", path.isEmpty, let first = found.first {
                path.append(first)
            }
            #endif
        } catch {
            fault = error.localizedDescription
            model.record("GET /api/search", error)
        }
    }

    /// Every organization at once; a failure in one fails the read, since a partial list would mislead.
    private static func search(_ client: GrafanaClient, orgs: [GrafanaOrg]) async throws -> [SearchHit] {
        try await withThrowingTaskGroup(of: [SearchHit].self) { group in
            for org in orgs {
                group.addTask { try await client.search("", org: org.orgId).map { $0.tagged(org) } }
            }
            var all: [SearchHit] = []
            for try await hits in group { all += hits }
            return all
        }
    }
}
