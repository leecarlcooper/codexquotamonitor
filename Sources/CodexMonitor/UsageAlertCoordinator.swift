import Foundation

final class UsageAlertCoordinator {
    private let thresholds = [25, 10]

    private var lastFiveHourNotified: Int?
    private var lastWeeklyNotified: Int?
    private var lastFiveResetText: String?
    private var lastWeeklyResetText: String?

    func handle(fiveHour: UsageLimit?, weekly: UsageLimit?) {
        handle(limit: fiveHour, name: "5-hour usage", lastNotified: &lastFiveHourNotified, lastResetText: &lastFiveResetText)
        handle(limit: weekly, name: "Weekly usage", lastNotified: &lastWeeklyNotified, lastResetText: &lastWeeklyResetText)
    }

    private func handle(limit: UsageLimit?, name: String, lastNotified: inout Int?, lastResetText: inout String?) {
        guard let limit else { return }
        if let resetText = normalize(limit.resetText), resetText != lastResetText {
            lastResetText = resetText
            lastNotified = nil
        }

        let percent = limit.percentRemaining
        if percent >= 90 {
            lastNotified = nil
        }

        for threshold in thresholds {
            if percent <= threshold, (lastNotified == nil || threshold < lastNotified!) {
                NotificationManager.shared.sendLowUsageNotification(
                    title: "\(name) low",
                    percent: percent,
                    resetText: limit.resetText
                )
                lastNotified = threshold
                break
            }
        }
    }

    private func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
