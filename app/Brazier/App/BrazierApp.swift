import SwiftUI
import UIKit

@main
struct BrazierApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        Chrome.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Brand.Tone.hot)
                .task {
                    AppDelegate.model = model
                    await model.push.refreshAuthorization()
                    await model.refresh()
                }
        }
    }
}

/// UIKit chrome the SwiftUI modifiers cannot reach: bars on ink, titles in Archivo.
enum Chrome {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Brand.Tone.ink)
        nav.shadowColor = UIColor(Brand.Tone.line)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(Brand.Tone.paper),
            .font: BrandFont.variable(family: "Archivo", size: 17, weight: 700),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Brand.Tone.paper),
            .font: BrandFont.variable(family: "Archivo", size: 34, weight: 900),
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Brand.Tone.ink)
        tab.shadowColor = UIColor(Brand.Tone.line)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Brand.Tone.muted)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Brand.Tone.muted), .font: BrandFont.variable(family: "Martian Mono", size: 10, weight: 500)]
        item.selected.iconColor = UIColor(Brand.Tone.hot)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Brand.Tone.hot), .font: BrandFont.variable(family: "Martian Mono", size: 10, weight: 500)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = .clear
        UITextField.appearance().tintColor = UIColor(Brand.Tone.hot)
    }
}
