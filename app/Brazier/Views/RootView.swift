import SwiftUI

/// The walkthrough until there is a server; the three tabs after. Removing the last server brings it back.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .alerts
    @State private var setup: Bool

    enum Tab: Hashable { case alerts, dashboards, settings }

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
