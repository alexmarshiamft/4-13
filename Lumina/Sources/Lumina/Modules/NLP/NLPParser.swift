// NLPParser.swift – On-device natural language parsing for Quick Capture
// Lumina: AI-powered reminders, task management, and focus app
//
// Uses Apple's NaturalLanguage framework (entirely on-device, no network calls).
// Parses free-form text like:
//   "Review design files before tomorrow at 10 AM"
//   "Call dentist next Friday at 2 PM #health urgent"
//   "Read chapter 3 every Monday at 8 PM"

import Foundation
import NaturalLanguage

// MARK: - Parsed Task Result
struct ParsedTaskResult {
    var title: String
    var dueDate: Date?
    var dueTime: Date?
    var associatedCalendarTitle: String?
    var priority: TaskPriority
    var tags: [String]
    var isRecurring: Bool
    var recurrenceRule: RecurrenceRule?
    var confidence: Double   // 0.0 – 1.0
}

// MARK: - NLPParser
/// Parses a natural language string into structured task components using on-device NLP.
final class NLPParser {

    // MARK: - Singleton
    static let shared = NLPParser()
    private init() { setup() }

    // MARK: - Private State
    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .tokenType])
    private let languageRecognizer = NLLanguageRecognizer()

    // Relative-date keywords → day offset
    private let relativeDayMap: [String: Int] = [
        "today": 0, "tonight": 0,
        "tomorrow": 1, "tmr": 1, "tmrw": 1,
        "overmorrow": 2,
        "yesterday": -1
    ]

    // Named weekdays → weekday component (1=Sun…7=Sat)
    private let weekdayMap: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]

    // Priority keywords
    private let priorityMap: [String: TaskPriority] = [
        "urgent": .urgent, "asap": .urgent, "critical": .urgent,
        "high": .high, "important": .high,
        "medium": .medium, "normal": .medium,
        "low": .low, "someday": .low
    ]

    private func setup() {
        tagger.string = ""
    }

    // MARK: - Public Parse API
    func parse(_ input: String) -> ParsedTaskResult {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var working = normalized

        let tags = extractTags(from: &working)
        let priority = extractPriority(from: &working)
        let (dueDate, dueTime, recurrenceRule, isRecurring) = extractDateTimeRecurrence(from: &working)
        let calendarTitle = extractCalendarReference(from: working)
        let title = cleanTitle(working)

        return ParsedTaskResult(
            title: title,
            dueDate: dueDate,
            dueTime: dueTime,
            associatedCalendarTitle: calendarTitle,
            priority: priority,
            tags: tags,
            isRecurring: isRecurring,
            recurrenceRule: recurrenceRule,
            confidence: computeConfidence(title: title, dueDate: dueDate)
        )
    }

    // MARK: - Tag Extraction (#tag)
    private func extractTags(from text: inout String) -> [String] {
        let pattern = #"#(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var tags: [String] = []
        for match in matches.reversed() {
            if let r = Range(match.range(at: 1), in: text) {
                tags.append(String(text[r]).lowercased())
            }
            if let r = Range(match.range, in: text) {
                text.removeSubrange(r)
            }
        }
        return tags.reversed()
    }

    // MARK: - Priority Extraction
    private func extractPriority(from text: inout String) -> TaskPriority {
        let lower = text.lowercased()
        for (keyword, priority) in priorityMap {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range, in: text) {
                text.removeSubrange(r)
                text = text.trimmingCharacters(in: .whitespaces)
                return priority
            }
        }
        _ = lower  // suppress unused warning
        return .none
    }

    // MARK: - Date / Time / Recurrence Extraction
    private func extractDateTimeRecurrence(
        from text: inout String
    ) -> (Date?, Date?, RecurrenceRule?, Bool) {
        var result: (Date?, Date?, RecurrenceRule?, Bool) = (nil, nil, nil, false)

        // ── Recurrence patterns first (e.g. "every Monday", "every 3rd Friday") ──
        if let rule = parseRecurrenceRule(from: &text) {
            result.2 = rule
            result.3 = true
        }

        // ── Relative day (tomorrow, today, …) ────────────────────────────────
        for (keyword, offset) in relativeDayMap {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range, in: text) {
                result.0 = Calendar.current.date(byAdding: .day, value: offset, to: Date())
                text.removeSubrange(r)
                text = text.trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // ── Named weekday (next Friday, this Monday, …) ───────────────────────
        if result.0 == nil {
            for (name, weekday) in weekdayMap {
                let pattern = "\\b(?:next\\s+|this\\s+)?\(NSRegularExpression.escapedPattern(for: name))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let r = Range(match.range, in: text) {
                    let wantsNext = text[r].lowercased().hasPrefix("next")
                    result.0 = nextWeekday(weekday, forceNext: wantsNext)
                    text.removeSubrange(r)
                    text = text.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // ── Absolute date (MM/DD, DD/MM, Month D, …) ─────────────────────────
        if result.0 == nil {
            result.0 = parseAbsoluteDate(from: &text)
        }

        // ── Time (10 AM, 2:30 PM, 14:00, …) ──────────────────────────────────
        result.1 = parseTime(from: &text)

        // ── "before …" qualifier: extract and apply to date ──────────────────
        let beforePattern = #"\bbefore\s+"#
        if let regex = try? NSRegularExpression(pattern: beforePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range, in: text) {
            text.removeSubrange(r)
            text = text.trimmingCharacters(in: .whitespaces)
        }

        return result
    }

    // MARK: - Recurrence Rule Parsing
    private func parseRecurrenceRule(from text: inout String) -> RecurrenceRule? {
        // "every day" / "daily"
        let dailyPattern = #"\b(?:every\s+day|daily)\b"#
        if matches(dailyPattern, in: text) {
            remove(dailyPattern, from: &text)
            return RecurrenceRule(frequency: .daily, interval: 1)
        }

        // "every N days"
        let everyNDaysPattern = #"\bevery\s+(\d+)\s+days?\b"#
        if let (match, groups) = firstMatch(everyNDaysPattern, in: text), let nStr = groups[safe: 0], let n = Int(nStr) {
            remove(match, from: &text)
            return RecurrenceRule(frequency: .daily, interval: n)
        }

        // "every week" / "weekly"
        let weeklyPattern = #"\b(?:every\s+week|weekly)\b"#
        if matches(weeklyPattern, in: text) {
            remove(weeklyPattern, from: &text)
            return RecurrenceRule(frequency: .weekly, interval: 1)
        }

        // "every Monday" / "every Monday and Wednesday"
        let everyDayPattern = #"\bevery\s+((?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)(?:(?:\s+and\s+|\s*,\s*)(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun))*)\b"#
        if let (match, groups) = firstMatch(everyDayPattern, in: text, options: .caseInsensitive),
           let daysStr = groups[safe: 0] {
            let dayNames = daysStr.components(separatedBy: CharacterSet(charactersIn: ", ").union(.init(charactersIn: "and")))
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            let days = dayNames.compactMap { weekdayMap[$0] }
            if !days.isEmpty {
                remove(match, from: &text)
                return RecurrenceRule(frequency: .weekly, interval: 1, daysOfWeek: days)
            }
        }

        // "every 3rd Friday" / "every second Tuesday"
        let ordinalDayPattern = #"\bevery\s+(1st|2nd|3rd|4th|5th|first|second|third|fourth|fifth)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        if let (match, groups) = firstMatch(ordinalDayPattern, in: text, options: .caseInsensitive),
           let ordinalStr = groups[safe: 0],
           let dayStr = groups[safe: 1] {
            let week = ordinalToInt(ordinalStr)
            let day = weekdayMap[dayStr.lowercased()]
            if let week, let day {
                remove(match, from: &text)
                return RecurrenceRule(frequency: .monthly, interval: 1, daysOfWeek: [day], weekOfMonth: week)
            }
        }

        // "every month" / "monthly"
        let monthlyPattern = #"\b(?:every\s+month|monthly)\b"#
        if matches(monthlyPattern, in: text) {
            remove(monthlyPattern, from: &text)
            return RecurrenceRule(frequency: .monthly, interval: 1)
        }

        // "every 3 months"
        let everyNMonthsPattern = #"\bevery\s+(\d+)\s+months?\b"#
        if let (match, groups) = firstMatch(everyNMonthsPattern, in: text), let nStr = groups[safe: 0], let n = Int(nStr) {
            remove(match, from: &text)
            return RecurrenceRule(frequency: .monthly, interval: n)
        }

        return nil
    }

    // MARK: - Time Parsing
    private func parseTime(from text: inout String) -> Date? {
        // "at 10 AM", "at 2:30 PM", "at 14:00", "10am", "2:30pm"
        let patterns: [String] = [
            #"\bat\s+(\d{1,2}):(\d{2})\s*(am|pm)?\b"#,
            #"\bat\s+(\d{1,2})\s*(am|pm)\b"#,
            #"\b(\d{1,2}):(\d{2})\s*(am|pm)\b"#,
            #"\b(\d{1,2})(am|pm)\b"#
        ]

        for pattern in patterns {
            if let (match, groups) = firstMatch(pattern, in: text, options: .caseInsensitive) {
                var hour = Int(groups[safe: 0] ?? "0") ?? 0
                let minute = Int(groups[safe: 1] ?? "0") ?? 0
                let meridiem = (groups.last ?? "").lowercased()

                if meridiem == "pm" && hour < 12 { hour += 12 }
                if meridiem == "am" && hour == 12 { hour = 0 }

                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = hour
                comps.minute = minute
                comps.second = 0

                remove(match, from: &text)
                text = text.trimmingCharacters(in: .whitespaces)
                return Calendar.current.date(from: comps)
            }
        }
        return nil
    }

    // MARK: - Absolute Date Parsing
    private func parseAbsoluteDate(from text: inout String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = ["MM/dd/yyyy", "dd/MM/yyyy", "MM/dd", "MMMM d", "MMM d", "MMMM d, yyyy"]
        for fmt in formats {
            formatter.dateFormat = fmt
            // try to find a candidate substring
            let words = text.components(separatedBy: .whitespaces)
            for length in stride(from: min(3, words.count), through: 1, by: -1) {
                for start in 0...(words.count - length) {
                    let candidate = words[start..<(start + length)].joined(separator: " ")
                    if let date = formatter.date(from: candidate) {
                        // Ensure year is current or future
                        let adjusted = ensureFutureDate(date, fmt: fmt)
                        // Remove matched words from text
                        let escapedCandidate = NSRegularExpression.escapedPattern(for: candidate)
                        remove("\\b\(escapedCandidate)\\b", from: &text)
                        return adjusted
                    }
                }
            }
        }
        return nil
    }

    private func ensureFutureDate(_ date: Date, fmt: String) -> Date {
        guard !fmt.contains("yyyy") else { return date }
        var comps = Calendar.current.dateComponents([.month, .day], from: date)
        comps.year = Calendar.current.component(.year, from: Date())
        let candidate = Calendar.current.date(from: comps) ?? date
        if candidate < Date() {
            comps.year = (comps.year ?? 0) + 1
            return Calendar.current.date(from: comps) ?? date
        }
        return candidate
    }

    // MARK: - Calendar Reference Extraction
    private func extractCalendarReference(from text: String) -> String? {
        // Look for "for <CalendarName> event", "before <CalendarName>", etc.
        let pattern = #"\bfor\s+([\w\s]+?)(?:\s+event|$)"#
        if let (_, groups) = firstMatch(pattern, in: text, options: .caseInsensitive),
           let title = groups[safe: 0] {
            let t = title.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    // MARK: - Title Cleanup
    private func cleanTitle(_ text: String) -> String {
        var clean = text
        // Remove common preposition phrases that often precede dates
        let prep = #"\b(?:before|by|on|at|for|until|due)\s*$"#
        if let regex = try? NSRegularExpression(pattern: prep, options: .caseInsensitive) {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capitalize first letter
        guard !clean.isEmpty else { return clean }
        return clean.prefix(1).uppercased() + clean.dropFirst()
    }

    // MARK: - Confidence Score
    private func computeConfidence(title: String, dueDate: Date?) -> Double {
        var score = 0.5
        if !title.isEmpty { score += 0.2 }
        if title.count > 5 { score += 0.1 }
        if dueDate != nil { score += 0.2 }
        return min(score, 1.0)
    }

    // MARK: - Helpers
    private func nextWeekday(_ targetWeekday: Int, forceNext: Bool) -> Date {
        var comps = DateComponents()
        comps.weekday = targetWeekday
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let currentWeekday = cal.component(.weekday, from: today)

        var daysAhead = targetWeekday - currentWeekday
        if daysAhead <= 0 || forceNext {
            daysAhead += 7
        }
        return cal.date(byAdding: .day, value: daysAhead, to: today) ?? today
    }

    private func ordinalToInt(_ ordinal: String) -> Int? {
        switch ordinal.lowercased() {
        case "1st", "first":  return 1
        case "2nd", "second": return 2
        case "3rd", "third":  return 3
        case "4th", "fourth": return 4
        case "5th", "fifth":  return 5
        default: return nil
        }
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> (String, [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let matchStr = String(text[Range(match.range, in: text)!])
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return (matchStr, groups)
    }

    private func remove(_ pattern: String, from text: inout String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        text = text.trimmingCharacters(in: .whitespaces)
    }
}
