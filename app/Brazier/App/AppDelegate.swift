import UIKit
import UserNotifications

/// Owns the one AppModel: created at launch, before any view, so a notification action taken from
/// the lock screen while the app is not running has a model to act with.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let model = AppModel()
    private let notifications = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notifications
        PushManager.configureCategories()
        _ = Self.model // created here, before the first view reads the server list
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let model = Self.model
        model.push.apnsFault = nil
        guard model.push.deviceToken != hex else { return }
        model.push.deviceToken = hex
        Task { await model.registerPush() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Self.model.push.apnsFault = error.localizedDescription
    }
}

/// Foreground presentation and taps or actions on a push. Hops to the model on the main actor.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = BrazierPush(userInfo: userInfo) else { return }
        let action = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? nil : response.actionIdentifier
        await AppDelegate.model.handlePush(payload, action: action)
    }
}
