import SwiftUI

/// The walkthrough until there is a server; after that the three sections: tabs on a phone, a
/// sidebar with a list column and a detail column on a wide screen. Removing the last server
/// brings the walkthrough back.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: Tab = .alerts
    @State private var setup: Bool

    enum Tab: Hashable, CaseIterable, Identifiable {
        case alerts, dashboards, settings

        var id: Self { self }
        var title: String {
            switch self {
            case .alerts: return "Alerts"
            case .dashboards: return "Dashboards"
            case .settings: return "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .alerts: return "bell"
            case .dashboards: return "rectangle.grid.2x2"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    init() {
        _setup = State(initialValue: !ServerStore.hasStoredServers)
    }

    var body: some View {
        Group {
            if setup {
                OnboardingFlow(includeWelcome: true) {
                    setup = false
                    tab = .alerts
                    Task { await model.refresh() }
                }
            } else if sizeClass == .regular {
                SplitRoot(section: $tab)
            } else {
                tabs
            }
        }
        .background(Brand.Tone.ink)
        .onChange(of: model.store.servers.isEmpty) { _, empty in
            if empty { setup = true }
        }
        .onChange(of: model.pendingAlert) { _, alert in
            if alert != nil { tab = .alerts }
        }
        #if DEBUG
        .onAppear {
            // Screenshot hook: with a seeded server, BRAZIER_SHOT=dashboards|notifications opens that section.
            switch ProcessInfo.processInfo.environment["BRAZIER_SHOT"] ?? "" {
            case "dashboards", "dashboard", "tiles": tab = .dashboards
            case "notifications", "settings-notifications": tab = .settings
            default: break
            }
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(Tab.alerts)
            DashboardsView()
                .tabItem { Label("Dashboards", systemImage: "rectangle.grid.2x2") }
                .tag(Tab.dashboards)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
        }
    }
}

/// The wide layout: the mark and the three sections down the side, the section's list in the middle,
/// what was picked on the right. A tapped push lands in the detail column the same as on a phone.
struct SplitRoot: View {
    @Environment(AppModel.self) private var model
    @Binding var section: RootView.Tab
    @State private var alert: GrafanaAlert?
    @State private var hit: SearchHit?
    @State private var page: SettingsPage?
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(Brand.Tone.ink)
        .onChange(of: model.pendingAlert) { _, pending in
            guard let pending else { return }
            section = .alerts
            alert = pending
            model.pendingAlert = nil
        }
    }

    private var sidebar: some View {
        List(selection: Binding(get: { Optional(section) }, set: { if let s = $0 { section = s } })) {
            ForEach(RootView.Tab.allCases) { tab in
                HStack(spacing: Brand.Space.label) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 24)
                    Text(tab.title).font(BrandFont.mono(12, weight: 500))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(section == tab ? Brand.Tone.hot : Brand.Tone.muted)
                .frame(minHeight: Brand.hitTarget)
                .tag(tab)
                .listRowBackground(section == tab ? Brand.Tone.raise : Brand.Tone.ink)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.Tone.ink)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderMark()
                    .padding(.horizontal, Brand.Space.card)
                    .padding(.vertical, Brand.Space.label)
                Hairline()
            }
            .background(Brand.Tone.ink)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .alerts: AlertsView(selection: $alert)
        case .dashboards: DashboardsView(selection: $hit)
        case .settings: SettingsView(selection: $page)
        }
    }

    @ViewBuilder private var detail: some View {
        Group {
            switch section {
            case .alerts:
                if let alert {
                    NavigationStack { AlertDetailView(alert: alert) }
                } else {
                    NavigationStack { BlankBay(title: "Pick an alert", text: "Its labels, its summary and the silence control open here.").background(Brand.Tone.ink) }
                }
            case .dashboards:
                if let hit {
                    NavigationStack { DashboardView(hit: hit) }
                } else {
                    NavigationStack { BlankBay(title: "Pick a dashboard", text: "Its tiles, or Grafana's own page, open here.").background(Brand.Tone.ink) }
                }
            case .settings:
                switch page {
                case .servers: NavigationStack { ServersView() }
                case .notifications: NavigationStack { NotificationsView() }
                case nil: NavigationStack { BlankBay(title: "Settings", text: "Servers and notifications open here.").background(Brand.Tone.ink) }
                }
            }
        }
        .background(Brand.Tone.ink)
    }
}
