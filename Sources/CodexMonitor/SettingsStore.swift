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
        let canRegister = LoginItemManager.canRegisterLoginItem
        self.canRegisterLoginItem = canRegister

        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: Keys.launchAtLogin) as? Bool {
            self.launchAtLogin = stored
        } else {
            let shouldEnable = canRegister
            self.launchAtLogin = shouldEnable
            defaults.set(shouldEnable, forKey: Keys.launchAtLogin)
        }
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
