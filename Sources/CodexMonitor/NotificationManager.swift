import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    static let isSupported: Bool = {
        AppEnvironment.isBundledApp
    }()

    private var center: UNUserNotificationCenter?

    private override init() {
        super.init()
        if Self.isSupported {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            self.center = center
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard let center else {
            completion?(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion?(granted)
        }
    }

    func sendLowUsageNotification(title: String, percent: Int, resetText: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        var body = "Remaining: \(percent)%"
        if let resetText, !resetText.isEmpty {
            body += " • Resets \(resetText)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
