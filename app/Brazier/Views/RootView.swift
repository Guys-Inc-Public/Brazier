import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .alerts

    enum Tab: Hashable { case alerts, dashboards, settings }

    var body: some View {
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
        .background(Brand.Tone.ink)
        .onChange(of: model.pendingAlert) { _, alert in
            if alert != nil { tab = .alerts }
        }
    }
}
