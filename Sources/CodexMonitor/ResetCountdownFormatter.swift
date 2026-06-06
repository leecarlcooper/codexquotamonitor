import Foundation

enum ResetCountdownFormatter {
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
        let pattern = "\\b(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\\b"
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
