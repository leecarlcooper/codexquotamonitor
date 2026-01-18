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

    @Published var loginItemMessage: String?

    let canRegisterLoginItem: Bool

    init() {
        self.canRegisterLoginItem = LoginItemManager.canRegisterLoginItem
        self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
    }

    func applyStartup() {
        if launchAtLogin {
            loginItemMessage = LoginItemManager.setEnabled(true)
        }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
    }
}
