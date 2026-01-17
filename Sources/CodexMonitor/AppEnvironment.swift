import Foundation

enum AppEnvironment {
    static let isBundledApp: Bool = {
        Bundle.main.bundleURL.pathExtension == "app"
    }()

    static let isInApplicationsFolder: Bool = {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Applications/")
    }()

    static let supportsLoginItems: Bool = {
        isBundledApp && isInApplicationsFolder
    }()
}
