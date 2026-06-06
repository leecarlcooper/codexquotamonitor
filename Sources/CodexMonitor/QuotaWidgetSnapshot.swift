import Foundation

enum QuotaWidgetStore {
    static let widgetKind = "CodexQuotaWidget"
    static let appGroupSuiteName = "group.com.codexmonitor.app"
    static let widgetBundleIdentifier = "com.codexmonitor.app.widget"
    private static let fallbackSuiteName = "com.codexmonitor.widget"
    private static let snapshotKey = "quotaWidgetSnapshot"
    private static let snapshotFileName = "quota-widget-snapshot.json"
    private static let snapshotDirectoryName = "CodexMonitor"

    static func save(_ snapshot: QuotaWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        for defaults in defaultsStores {
            defaults.set(data, forKey: snapshotKey)
        }
        for fileURL in snapshotWriteFileURLs {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func load() -> QuotaWidgetSnapshot? {
        for defaults in defaultsStores {
            guard let data = defaults.data(forKey: snapshotKey),
                  let snapshot = try? JSONDecoder().decode(QuotaWidgetSnapshot.self, from: data)
            else { continue }
            return snapshot
        }
        for fileURL in snapshotReadFileURLs {
            guard let data = try? Data(contentsOf: fileURL),
                  let snapshot = try? JSONDecoder().decode(QuotaWidgetSnapshot.self, from: data)
            else { continue }
            return snapshot
        }
        return nil
    }

    private static var defaultsStores: [UserDefaults] {
        [
            UserDefaults(suiteName: appGroupSuiteName),
            UserDefaults(suiteName: fallbackSuiteName)
        ].compactMap { $0 }
    }

    private static var snapshotReadFileURLs: [URL] {
        uniqueURLs([
            appGroupSnapshotURL,
            currentProcessSnapshotURL,
            widgetContainerSnapshotURL
        ])
    }

    private static var snapshotWriteFileURLs: [URL] {
        uniqueURLs([
            appGroupSnapshotURL,
            currentProcessSnapshotURL,
            widgetContainerSnapshotURL
        ])
    }

    private static var appGroupSnapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent(snapshotFileName)
    }

    private static var currentProcessSnapshotURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent(snapshotFileName)
    }

    private static var widgetContainerSnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent(snapshotFileName)
    }

    private static func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { $0 }.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

struct QuotaWidgetSnapshot: Codable, Equatable {
    let codex: QuotaProductSnapshot
    let claude: QuotaProductSnapshot
    let selectedProduct: QuotaProduct
    let savedAt: Date

    static let placeholder = QuotaWidgetSnapshot(
        codex: QuotaProductSnapshot(
            product: .codex,
            shortTitle: "5 hour limit",
            weeklyTitle: "Weekly limit",
            shortLimit: QuotaLimitSnapshot(percentRemaining: 62, resetText: "2h 14m"),
            weeklyLimit: QuotaLimitSnapshot(percentRemaining: 84, resetText: "3d 4h"),
            authState: .authenticated,
            errorMessage: nil,
            lastUpdated: Date()
        ),
        claude: QuotaProductSnapshot(
            product: .claude,
            shortTitle: "Current session",
            weeklyTitle: "Weekly limits",
            shortLimit: QuotaLimitSnapshot(percentRemaining: 22, resetText: "47m"),
            weeklyLimit: QuotaLimitSnapshot(percentRemaining: 9, resetText: "5d"),
            authState: .authenticated,
            errorMessage: nil,
            lastUpdated: Date()
        ),
        selectedProduct: .codex,
        savedAt: Date()
    )

    static let empty = QuotaWidgetSnapshot(
        codex: QuotaProductSnapshot(
            product: .codex,
            shortTitle: "5 hour limit",
            weeklyTitle: "Weekly limit",
            shortLimit: nil,
            weeklyLimit: nil,
            authState: .unknown,
            errorMessage: "Waiting for update",
            lastUpdated: nil
        ),
        claude: QuotaProductSnapshot(
            product: .claude,
            shortTitle: "Current session",
            weeklyTitle: "Weekly limits",
            shortLimit: nil,
            weeklyLimit: nil,
            authState: .unknown,
            errorMessage: "Waiting for update",
            lastUpdated: nil
        ),
        selectedProduct: .codex,
        savedAt: Date()
    )

    func preservingLastKnownValues(from previous: QuotaWidgetSnapshot?) -> QuotaWidgetSnapshot {
        guard let previous else { return self }
        let nextCodex = codex.preservingLastKnownValues(from: previous.codex)
        let nextClaude = claude.preservingLastKnownValues(from: previous.claude)
        let didPreserveEverything = nextCodex == previous.codex && nextClaude == previous.claude

        return QuotaWidgetSnapshot(
            codex: nextCodex,
            claude: nextClaude,
            selectedProduct: selectedProduct,
            savedAt: didPreserveEverything ? previous.savedAt : savedAt
        )
    }
}

struct QuotaProductSnapshot: Codable, Equatable {
    let product: QuotaProduct
    let shortTitle: String
    let weeklyTitle: String
    let shortLimit: QuotaLimitSnapshot?
    let weeklyLimit: QuotaLimitSnapshot?
    let authState: QuotaAuthState
    let errorMessage: String?
    let lastUpdated: Date?

    func preservingLastKnownValues(from previous: QuotaProductSnapshot) -> QuotaProductSnapshot {
        guard shouldPreservePreviousValues else { return self }
        return QuotaProductSnapshot(
            product: product,
            shortTitle: shortTitle,
            weeklyTitle: weeklyTitle,
            shortLimit: previous.shortLimit,
            weeklyLimit: previous.weeklyLimit,
            authState: previous.authState,
            errorMessage: previous.errorMessage,
            lastUpdated: previous.lastUpdated
        )
    }

    private var shouldPreservePreviousValues: Bool {
        authState == .unknown && shortLimit == nil && weeklyLimit == nil
    }
}

struct QuotaLimitSnapshot: Codable, Equatable {
    let percentRemaining: Int
    let resetText: String
}

enum QuotaProduct: String, Codable, Equatable {
    case codex
    case claude
}

enum QuotaAuthState: String, Codable, Equatable {
    case unknown
    case authenticated
    case needsLogin
}
