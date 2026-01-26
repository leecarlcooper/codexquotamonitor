import SwiftUI
import AppKit
import Foundation

struct PopoverView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var claudeUsageService: UsageService
    @ObservedObject var settings: SettingsStore
    let onSignIn: () -> Void
    let onClaudeSignIn: () -> Void
    let onRefresh: () -> Void
    let onLogout: () -> Void

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
                claudeSection
                settingsSeparator
                settingsSection
                footer
            }
            .padding(18)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: 340, height: 700)
    }

    private var header: some View {
        HStack {
            selectionButton(for: .codex)
            Text("Codex")
                .font(.system(size: 17, weight: .semibold))
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(usageService.usageURL)
                }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        usageContent(
            for: usageService,
            signInLabel: "Open Codex Sign In",
            signInAction: onSignIn,
            titles: ("5 hour limit", "Weekly limit"),
            palette: .codex
        )
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                selectionButton(for: .claude)
                Text("Claude")
                    .font(.system(size: 15, weight: .semibold))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.open(claudeUsageService.usageURL)
                    }
            }
            usageContent(
                for: claudeUsageService,
                signInLabel: "Open Claude Sign In",
                signInAction: onClaudeSignIn,
                titles: ("Current session", "Weekly limits"),
                palette: .claude
            )
        }
    }

    @ViewBuilder
    private func usageContent(
        for service: UsageService,
        signInLabel: String,
        signInAction: @escaping () -> Void,
        titles: (String, String),
        palette: UsageBarPalette
    ) -> some View {
        if service.authState == .needsLogin {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to view limits")
                    .font(.system(size: 14, weight: .medium))
                Button(action: signInAction) {
                    Text(signInLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else if service.fiveHourLimit == nil && service.weeklyLimit == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading usage…")
                    .font(.system(size: 14, weight: .medium))
                Button(action: signInAction) {
                    Text(signInLabel)
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
                    title: titles.0,
                    limit: service.fiveHourLimit,
                    referenceDate: service.lastUpdated,
                    showTitle: true,
                    palette: palette
                )
                UsageCard(
                    title: titles.1,
                    limit: service.weeklyLimit,
                    referenceDate: service.lastUpdated,
                    showTitle: true,
                    palette: palette
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

    private var settingsSeparator: some View {
        Divider()
            .opacity(0.5)
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
            Button("Log out") {
                onLogout()
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
    let palette: UsageBarPalette

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            cardBody(now: context.date)
        }
    }

    private var percentText: String {
        guard let percent = limit?.percent else { return "--%" }
        return "\(percent)%"
    }

    private var metricText: String {
        limit?.metric.label ?? "remaining"
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
                Text(metricText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            UsageBar(fillPercent: limit?.percent, stylePercent: limit?.percent, palette: palette)
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

        let normalized = normalize(trimmed)
        if let interval = parseInterval(from: normalized, now: now, referenceDate: referenceDate, calendar: calendar) {
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
        if let weekdayDate = parseWeekdayDate(from: text, now: now, calendar: calendar) {
            return weekdayDate.timeIntervalSince(now)
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

    private static func parseWeekdayDate(from text: String, now: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased()
        let pattern = "\\\\b(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\\\\b"
        let token: String
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower) {
            token = String(lower[range])
        } else {
            let candidates = [
                "sunday", "sun",
                "monday", "mon",
                "tuesday", "tue",
                "wednesday", "wed",
                "thursday", "thu",
                "friday", "fri",
                "saturday", "sat"
            ]
            guard let found = candidates.first(where: { lower.contains($0) }) else { return nil }
            token = found
        }
        let weekdayMap: [String: Int] = [
            "sun": 1, "sunday": 1,
            "mon": 2, "monday": 2,
            "tue": 3, "tuesday": 3,
            "wed": 4, "wednesday": 4,
            "thu": 5, "thursday": 5,
            "fri": 6, "friday": 6,
            "sat": 7, "saturday": 7
        ]

        guard let weekday = weekdayMap[token] else { return nil }
        let time = parseTimeComponents(from: text) ?? DateComponents(hour: 0, minute: 0)

        var components = DateComponents()
        components.weekday = weekday
        components.hour = time.hour
        components.minute = time.minute

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            direction: .forward
        )
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
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
    let fillPercent: Int?
    let stylePercent: Int?
    let palette: UsageBarPalette

    private var clamped: CGFloat {
        CGFloat(max(0, min(100, fillPercent ?? 0))) / 100
    }

    private var resolvedBarColor: Color {
        UsageBarStyle.swiftUIColor(for: stylePercent, palette: palette)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 6)
                    .fill(resolvedBarColor)
                    .frame(width: proxy.size.width * clamped)
            }
        }
    }
}

private extension PopoverView {
    func selectionButton(for source: UsageSource) -> some View {
        Button(action: { settings.selectedUsageSource = source }) {
            Image(systemName: settings.selectedUsageSource == source ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source == .codex ? "Show Codex in menu bar" : "Show Claude in menu bar")
    }
}
