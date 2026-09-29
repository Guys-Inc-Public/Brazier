import Foundation
import Observation
import UIKit
import UserNotifications

/// Permission, the APNs token, the notification category with its actions, and the
/// state of the last relay registration. Nothing here is optimistic: `registration`
/// only says PASS after the relay answered.
@MainActor
@Observable
final class PushManager {
    static let category = "ALERT"
    static let actions: [(id: String, title: String, hours: Int)] = [
        ("SILENCE_1H", "Silence 1 h", 1),
        ("SILENCE_8H", "Silence 8 h", 8),
        ("SILENCE_24H", "Silence 24 h", 24),
    ]

    enum Registration: Equatable {
        case none
        case pending
        case pass(Date)
        case refuse(String)
    }

    var deviceToken: String?
    var authorization: UNAuthorizationStatus = .notDetermined
    /// Per server: the state of this phone's registration with that server's relay. Nothing here is
    /// optimistic; PASS only after the relay answered.
    var registrations: [UUID: Registration] = [:]
    /// Per server: the Grafana login the relay filed this phone under, once it answered.
    var registeredAs: [UUID: String] = [:]
    /// Per server: the last hand-over of what to send (Settings › Notifications) to its relay.
    var preferences: [UUID: Registration] = [:]
    /// APNs itself refused to hand out a token; shown wherever a registration would be.
    var apnsFault: String?

    func registration(for server: UUID?) -> Registration {
        guard let server else { return .none }
        if let fault = apnsFault { return .refuse("APNs: \(fault)") }
        return registrations[server] ?? .none
    }

    func preferences(for server: UUID?) -> Registration {
        guard let server else { return .none }
        return preferences[server] ?? .none
    }

    static func configureCategories() {
        let actions = Self.actions.map {
            UNNotificationAction(identifier: $0.id, title: $0.title, options: [.authenticationRequired])
        }
        let category = UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    var authorizationWord: String {
        switch authorization {
        case .authorized: return "AUTHORIZED"
        case .provisional: return "PROVISIONAL"
        case .denied: return "DENIED"
        case .ephemeral: return "EPHEMERAL"
        case .notDetermined: return "NOT ASKED"
        @unknown default: return "UNKNOWN"
        }
    }

    var authorizationSignal: Signal {
        switch authorization {
        case .authorized, .provisional: return .ok
        case .denied: return .stop
        default: return .none
        }
    }

    /// Which APNs host the relay must use for this build. A development profile
    /// means the sandbox; TestFlight and the store carry production.
    static var apnsEnvironment: String {
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1),
           text.range(of: "aps-environment</key>\\s*<string>development", options: .regularExpression) != nil {
            return "sandbox"
        }
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// A local notification carrying the outcome of an action taken from the lock screen.
    static func notifyOutcome(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
