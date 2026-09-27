import Darwin
import Foundation

struct QuotaStatusSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let selectedUsageSource: String
    let codex: ProductStatus
    let claude: ProductStatus

    init(
        generatedAt: Date = Date(),
        selectedUsageSource: UsageSource,
        codexService: UsageService,
        claudeService: UsageService
    ) {
        self.schemaVersion = 1
        self.generatedAt = generatedAt
        self.selectedUsageSource = selectedUsageSource.rawValue
        self.codex = ProductStatus(service: codexService)
        self.claude = ProductStatus(service: claudeService)
    }
}

extension QuotaStatusSnapshot {
    struct ProductStatus: Codable {
        let productName: String
        let authState: String
        let statusSummary: String
        let fiveHourLimit: LimitStatus?
        let weeklyLimit: LimitStatus?
        let lastUpdated: Date?
        let errorMessage: String?

        init(service: UsageService) {
            self.productName = service.configuration.productName
            self.authState = service.authState.statusValue
            self.statusSummary = service.statusSummary
            self.fiveHourLimit = service.fiveHourLimit.map(LimitStatus.init(limit:))
            self.weeklyLimit = service.weeklyLimit.map(LimitStatus.init(limit:))
            self.lastUpdated = service.lastUpdated
            self.errorMessage = service.errorMessage
        }
    }

    struct LimitStatus: Codable {
        let percent: Int
        let metric: UsageMetric
        let percentRemaining: Int
        let resetText: String
        let resetAt: String?

        init(limit: UsageLimit) {
            self.percent = limit.percent
            self.metric = limit.metric
            self.percentRemaining = limit.percentRemaining
            self.resetText = limit.resetText
            self.resetAt = ISO8601DateFormatter().date(from: limit.resetText) == nil ? nil : limit.resetText
        }
    }
}

final class QuotaStatusStore {
    static let shared = QuotaStatusStore()

    static var statusFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("CodexMonitor", isDirectory: true)
            .appendingPathComponent("quota-status.json", isDirectory: false)
    }

    private let encoder: JSONEncoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    func write(_ snapshot: QuotaStatusSnapshot) throws {
        let url = Self.statusFileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    static func readStatusData() throws -> Data {
        try Data(contentsOf: statusFileURL)
    }
}

enum QuotaStatusCommand {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        let arguments = Set(arguments.dropFirst())

        if arguments.contains("--quota-status-path") {
            writeOutput(QuotaStatusStore.statusFileURL.path)
            return EXIT_SUCCESS
        }

        guard arguments.contains("--quota-status") else {
            return nil
        }

        do {
            let data = try QuotaStatusStore.readStatusData()
            FileHandle.standardOutput.write(data)
            writeOutput("")
            return EXIT_SUCCESS
        } catch {
            writeError("quota_status_error=\(error.localizedDescription)")
            writeError("quota_status_path=\(QuotaStatusStore.statusFileURL.path)")
            return EXIT_FAILURE
        }
    }

    private static func writeOutput(_ line: String) {
        if let data = "\(line)\n".data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }

    private static func writeError(_ line: String) {
        if let data = "\(line)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

private extension UsageService.AuthState {
    var statusValue: String {
        switch self {
        case .unknown:
            return "unknown"
        case .authenticated:
            return "authenticated"
        case .needsLogin:
            return "needsLogin"
        }
    }
}
