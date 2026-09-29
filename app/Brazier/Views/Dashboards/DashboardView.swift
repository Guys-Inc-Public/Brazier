import SwiftUI

/// One dashboard: its stat panels as native tiles, or Grafana's own page. Tiles lead when the
/// dashboard has any; the choice is remembered per dashboard.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    @State private var document: DashboardDocument?
    @State private var mode: Mode = .tiles
    @State private var fault: String?
    @State private var starred: Bool?
    @State private var starring = false

    enum Mode: String, CaseIterable, Identifiable {
        case tiles, page
        var id: String { rawValue }
        var word: String { self == .tiles ? "Tiles" : "Page" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if document != nil {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.word).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Brand.Space.card)
                .padding(.vertical, Brand.Space.inline)
                Hairline()
            }
            Group {
                if let document {
                    switch mode {
                    case .tiles: TilesView(hit: hit, document: document)
                    case .page: DashboardWebView(hit: hit)
                    }
                } else if fault != nil {
                    // The JSON was refused (a viewer without that permission, an old Grafana): the page still works.
                    DashboardWebView(hit: hit)
                } else {
                    WarmingBay(name: hit.title)
                }
            }
        }
        .background(Brand.Tone.ink)
        .navigationTitle(hit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.selectedServer?.isAnonymous != true {
                ToolbarItem(placement: .topBarTrailing) { starButton }
            }
        }
        .onChange(of: mode) { _, new in UserDefaults.standard.set(new.rawValue, forKey: "dashboardMode.\(hit.uid)") }
        .task(id: hit.id) { starred = hit.isStarred; await load() }
    }

    /// Grafana's own star, for the signed-in user; starred dashboards lead the list.
    private var starButton: some View {
        Button {
            guard !starring else { return }
            let next = !(starred ?? false)
            starring = true
            Task {
                if case .pass = await model.setStar(hit, on: next) { starred = next }
                starring = false
            }
        } label: {
            Image(systemName: (starred ?? false) ? "star.fill" : "star")
                .foregroundStyle((starred ?? false) ? Brand.Tone.hot : Brand.Tone.muted)
        }
        .disabled(starring)
        .accessibilityLabel((starred ?? false) ? "Unstar" : "Star")
    }

    private func load() async {
        guard let server = model.selectedServer else { return }
        document = nil
        fault = nil
        do {
            let doc = try await model.client(for: server).dashboardJSON(uid: hit.uid, org: hit.orgId)
            if let kept = UserDefaults.standard.string(forKey: "dashboardMode.\(hit.uid)"), let m = Mode(rawValue: kept) {
                mode = m
            } else {
                mode = doc.tilePanels.isEmpty ? .page : .tiles
            }
            #if DEBUG
            switch ProcessInfo.processInfo.environment["BRAZIER_SHOT"] ?? "" {
            case "tiles": mode = .tiles
            case "dashboard": mode = .page
            default: break
            }
            #endif
            document = doc
        } catch {
            // The view went away or its task restarted mid-read: not a fault, and the restart reads again.
            guard !Task.isCancelled else { return }
            fault = error.localizedDescription
            model.record("GET /api/dashboards/uid/\(hit.uid)", error)
        }
    }
}
