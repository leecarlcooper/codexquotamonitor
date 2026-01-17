import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if launchAtLogin {
                loginItemMessage = LoginItemManager.setEnabled(true)
            } else {
                loginItemMessage = LoginItemManager.setEnabled(false)
            }
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled {
                guard NotificationManager.isSupported else {
                    notificationsMessage = "Notifications require the app bundle in /Applications."
                    notificationsEnabled = false
                    return
                }
                NotificationManager.shared.requestAuthorization { [weak self] granted in
                    if !granted {
                        DispatchQueue.main.async {
                            self?.notificationsMessage = "Notifications disabled in system settings."
                            self?.notificationsEnabled = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.notificationsMessage = nil
                        }
                    }
                }
            } else {
                notificationsMessage = nil
            }
        }
    }

    @Published var loginItemMessage: String?
    @Published var notificationsMessage: String?

    let canRegisterLoginItem: Bool

    init() {
        self.canRegisterLoginItem = LoginItemManager.canRegisterLoginItem
        self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        if notificationsEnabled && !NotificationManager.isSupported {
            notificationsEnabled = false
            notificationsMessage = "Notifications require the app bundle in /Applications."
        }
    }

    func applyStartup() {
        if launchAtLogin {
            loginItemMessage = LoginItemManager.setEnabled(true)
        }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let notificationsEnabled = "notificationsEnabled"
    }
}
