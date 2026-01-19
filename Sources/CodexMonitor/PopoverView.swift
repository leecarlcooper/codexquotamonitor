import SwiftUI
import AppKit
import Foundation

struct PopoverView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settings: SettingsStore
    let onSignIn: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 16) {
                header
                    .layoutPriority(1)
                content
                settingsSection
                footer
            }
            .padding(18)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: 340, height: 368)
    }

    private var header: some View {
        HStack {
            Text("Codex")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if usageService.authState == .needsLogin {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to view limits")
                    .font(.system(size: 14, weight: .medium))
                Button(action: onSignIn) {
                    Text("Open Sign In")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else if usageService.fiveHourLimit == nil && usageService.weeklyLimit == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading usage…")
                    .font(.system(size: 14, weight: .medium))
                Button(action: onSignIn) {
                    Text("Open Sign In")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 12) {
                UsageCard(
                    title: "5 hour limit",
                    limit: usageService.fiveHourLimit,
                    referenceDate: usageService.lastUpdated,
                    showTitle: true
                )
                UsageCard(
                    title: "Weekly limit",
                    limit: usageService.weeklyLimit,
                    referenceDate: usageService.lastUpdated,
                    showTitle: true
                )
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .disabled(!settings.canRegisterLoginItem)
        }
    }

    private var footer: some View {
        HStack {
            if let error = usageService.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if let lastUpdated = usageService.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Waiting for update...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Usage Page") {
                NSWorkspace.shared.open(UsageService.usageURL)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
    }
}

private struct UsageCard: View {
    let title: String
    let limit: UsageLimit?
    let referenceDate: Date?
    let showTitle: Bool

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            cardBody(now: context.date)
        }
    }

    private var percentText: String {
        guard let percent = limit?.percentRemaining else { return "--%" }
        return "\(percent)%"
    }

    private func resetText(now: Date) -> String {
        guard let limit, !limit.resetText.isEmpty else { return "Reset time unavailable" }
        guard let countdown = ResetCountdownFormatter.countdown(
            from: limit.resetText,
            now: now,
            referenceDate: referenceDate
        ) else {
            return "Reset time unavailable"
        }
        return "Resets in \(countdown)"
    }

    private func cardBody(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .layoutPriority(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percentText)
                    .font(.system(size: 24, weight: .bold))
                Text("remaining")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            UsageBar(percent: limit?.percentRemaining)
                .frame(height: 10)

            Text(resetText(now: now))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.black.opacity(0.12))
        .cornerRadius(12)
    }
}

private enum ResetCountdownFormatter {
    static func countdown(
        from resetText: String,
        now: Date = Date(),
        referenceDate: Date? = nil,
        calendar: Calendar = .current
    ) -> String? {
        let trimmed = resetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let interval = parseInterval(from: trimmed, now: now, referenceDate: referenceDate, calendar: calendar) {
            return format(interval: interval)
        }
        return nil
    }

    private static func parseInterval(
        from text: String,
        now: Date,
        referenceDate: Date?,
        calendar: Calendar
    ) -> TimeInterval? {
        if let relative = parseRelativeInterval(from: text, now: now, calendar: calendar) {
            if relative.isAnchored, let referenceDate {
                return referenceDate.addingTimeInterval(relative.interval).timeIntervalSince(now)
            }
            return relative.interval
        }
        if let absoluteDate = parseAbsoluteDate(from: text, now: now, calendar: calendar) {
            return absoluteDate.timeIntervalSince(now)
        }
        if let timeOnlyDate = parseTimeOnlyDate(from: text, now: now, calendar: calendar) {
            return timeOnlyDate.timeIntervalSince(now)
        }
        return nil
    }

    private static func parseRelativeInterval(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> (interval: TimeInterval, isAnchored: Bool)? {
        let lower = text.lowercased()
        if lower.contains("tomorrow") {
            if let target = parseDayKeyword("tomorrow", from: lower, now: now, calendar: calendar) {
                return (target.timeIntervalSince(now), false)
            }
        }
        if lower.contains("today") {
            if let target = parseDayKeyword("today", from: lower, now: now, calendar: calendar) {
                return (target.timeIntervalSince(now), false)
            }
        }

        let pattern = "(\\d+)\\s*(weeks?|w|days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
        if matches.isEmpty { return nil }

        var seconds: TimeInterval = 0
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower)
            else { continue }

            let value = Double(lower[valueRange]) ?? 0
            let unit = String(lower[unitRange])
            switch unit {
            case "week", "weeks", "w":
                seconds += value * 7 * 24 * 3600
            case "day", "days", "d":
                seconds += value * 24 * 3600
            case "hour", "hours", "hr", "hrs", "h":
                seconds += value * 3600
            case "minute", "minutes", "min", "mins", "m":
                seconds += value * 60
            default:
                break
            }
        }

        if seconds > 0 {
            return (seconds, true)
        }
        return nil
    }

    private static func parseDayKeyword(_ keyword: String, from text: String, now: Date, calendar: Calendar) -> Date? {
        let baseDate: Date
        switch keyword {
        case "tomorrow":
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case "today":
            baseDate = now
        default:
            baseDate = now
        }

        if let time = parseTimeComponents(from: text) {
            var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
            components.hour = time.hour
            components.minute = time.minute
            return calendar.date(from: components)
        }

        return calendar.startOfDay(for: baseDate)
    }

    private static func parseAbsoluteDate(from text: String, now: Date, calendar: Calendar) -> Date? {
        let formats = [
            "MMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy h:mm a",
            "MMMM d, yyyy h:mm a",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d 'at' h:mm a",
            "MMMM d 'at' h:mm a",
            "MMM d",
            "MMMM d"
        ]

        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone.current

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: text) else { continue }

            var date = parsed
            if !format.contains("y") {
                var components = calendar.dateComponents(in: timeZone, from: parsed)
                components.year = calendar.component(.year, from: now)
                if let adjusted = calendar.date(from: components) {
                    date = adjusted
                }
            }

            if date <= now {
                if let advanced = calendar.date(byAdding: .year, value: 1, to: date) {
                    date = advanced
                }
            }

            return date
        }

        return nil
    }

    private static func parseTimeOnlyDate(from text: String, now: Date, calendar: Calendar) -> Date? {
        guard let time = parseTimeComponents(from: text) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate <= now {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    private static func parseTimeComponents(from text: String) -> DateComponents? {
        let pattern = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        guard let match = regex.firstMatch(in: text.lowercased(), range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        guard let hourRange = Range(match.range(at: 1), in: text),
              let periodRange = Range(match.range(at: 3), in: text)
        else {
            return nil
        }

        let minute: Int
        if let minuteRange = Range(match.range(at: 2), in: text) {
            minute = Int(text[minuteRange]) ?? 0
        } else {
            minute = 0
        }

        var hour = Int(text[hourRange]) ?? 0
        let period = text[periodRange].lowercased()
        if period == "pm" && hour < 12 { hour += 12 }
        if period == "am" && hour == 12 { hour = 0 }

        return DateComponents(hour: hour, minute: minute)
    }

    private static func format(interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.up)))
        let totalMinutes = max(1, totalSeconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct UsageBar: View {
    let percent: Int?

    private var clamped: CGFloat {
        CGFloat(max(0, min(100, percent ?? 0))) / 100
    }

    private var barColor: Color {
        UsageBarStyle.swiftUIColor(for: percent)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 6)
                    .fill(barColor)
                    .frame(width: proxy.size.width * clamped)
            }
        }
    }
}
