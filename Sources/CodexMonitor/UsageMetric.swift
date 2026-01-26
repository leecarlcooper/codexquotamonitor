import Foundation

enum UsageMetric: String, Codable {
    case remaining
    case used

    var label: String {
        switch self {
        case .remaining:
            return "remaining"
        case .used:
            return "used"
        }
    }

    func remainingPercent(from percent: Int) -> Int {
        let clamped = max(0, min(100, percent))
        switch self {
        case .remaining:
            return clamped
        case .used:
            return max(0, min(100, 100 - clamped))
        }
    }
}

