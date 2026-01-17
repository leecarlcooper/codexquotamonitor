import Foundation
import ServiceManagement

enum LoginItemManager {
    static var canRegisterLoginItem: Bool {
        AppEnvironment.supportsLoginItems
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard canRegisterLoginItem else {
            return "Requires app bundle in /Applications."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
