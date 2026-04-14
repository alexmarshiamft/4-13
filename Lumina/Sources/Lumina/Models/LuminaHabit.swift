// LuminaHabit.swift – SwiftData model for a habit (with recurrence & streak tracking)
// Lumina: AI-powered reminders, task management, and focus app

import Foundation
import SwiftData

// MARK: - Habit Category
enum HabitCategory: String, Codable, CaseIterable {
    case health      = "health"
    case productivity = "productivity"
    case learning    = "learning"
    case mindfulness = "mindfulness"
    case fitness     = "fitness"
    case social      = "social"
    case finance     = "finance"
    case other       = "other"

    var systemImage: String {
        switch self {
        case .health:       return "heart.fill"
        case .productivity: return "checkmark.seal.fill"
        case .learning:     return "book.fill"
        case .mindfulness:  return "brain.head.profile"
        case .fitness:      return "figure.run"
        case .social:       return "person.2.fill"
        case .finance:      return "dollarsign.circle.fill"
        case .other:        return "star.fill"
        }
    }
}

// MARK: - Habit Frequency
enum HabitFrequency: String, Codable, CaseIterable {
    case daily        = "daily"
    case weekdays     = "weekdays"         // Mon–Fri
    case weekends     = "weekends"         // Sat–Sun
    case specificDays = "specific_days"    // user-defined days
    case weekly       = "weekly"           // once a week
    case monthly      = "monthly"          // once a month
    case custom       = "custom"           // fully custom via RecurrenceRule
}

// MARK: - LuminaHabit SwiftData Model
@Model
final class LuminaHabit {

    // ── Identity ──────────────────────────────────────────────────────────────
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // ── Content ───────────────────────────────────────────────────────────────
    var name: String
    var habitDescription: String
    var categoryRaw: String
    var emoji: String         // visual identifier

    // ── Scheduling ────────────────────────────────────────────────────────────
    var frequencyRaw: String
    var targetDaysOfWeek: [Int]   // 1=Sun … 7=Sat; used for .specificDays
    var reminderTime: Date?       // time-of-day for daily reminder
    var recurrenceRuleData: Data? // encoded RecurrenceRule for complex schedules

    // ── Streak & History ──────────────────────────────────────────────────────
    var currentStreak: Int
    var longestStreak: Int
    var totalCompletions: Int
    var lastCompletedDate: Date?
    var startDate: Date

    // ── Goal ──────────────────────────────────────────────────────────────────
    var dailyGoalCount: Int      // how many times per occurrence (e.g. 8 glasses of water)
    var unit: String?            // e.g. "glasses", "minutes", "pages"

    // ── State ─────────────────────────────────────────────────────────────────
    var isArchived: Bool
    var isPaused: Bool

    // ── Relationships ─────────────────────────────────────────────────────────
    @Relationship(deleteRule: .cascade)
    var entries: [HabitEntry] = []

    @Relationship(deleteRule: .cascade)
    var tasks: [LuminaTask] = []

    // MARK: - Computed Properties

    var category: HabitCategory {
        get { HabitCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var frequency: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var recurrenceRule: RecurrenceRule? {
        get {
            guard let data = recurrenceRuleData else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
        }
        set {
            recurrenceRuleData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Whether the habit has been completed today
    var isCompletedToday: Bool {
        guard let lastDate = lastCompletedDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    /// Completion rate over the last 30 days (0.0 … 1.0)
    var completionRate30Days: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = entries.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return 0 }
        let completed = recent.filter { $0.isCompleted }.count
        return Double(completed) / Double(recent.count)
    }

    /// Entry for a specific date, if it exists
    func entry(for date: Date) -> HabitEntry? {
        entries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// Whether the habit is scheduled on a given date
    func isScheduled(on date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch frequency {
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(weekday)   // Mon=2 … Fri=6
        case .weekends:
            return weekday == 1 || weekday == 7  // Sun=1, Sat=7
        case .specificDays:
            return targetDaysOfWeek.contains(weekday)
        case .weekly, .monthly, .custom:
            return recurrenceRule.map { isDateInRecurrence(date, rule: $0) } ?? false
        }
    }

    private func isDateInRecurrence(_ date: Date, rule: RecurrenceRule) -> Bool {
        // Simplified check — a production engine would compute next-occurrence dates
        switch rule.frequency {
        case .weekly:
            if let days = rule.daysOfWeek {
                let weekday = Calendar.current.component(.weekday, from: date)
                return days.contains(weekday)
            }
            return false
        case .monthly:
            if let week = rule.weekOfMonth, let days = rule.daysOfWeek {
                let weekday = Calendar.current.component(.weekday, from: date)
                let weekOfMonth = Calendar.current.component(.weekOfMonth, from: date)
                return days.contains(weekday) && weekOfMonth == week
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Streak Calculation
    /// Recalculate streak from entry history (call after any completion change)
    func recalculateStreak() {
        let sortedEntries = entries
            .filter { $0.isCompleted }
            .sorted { $0.date > $1.date }

        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        for entry in sortedEntries {
            let entryDay = Calendar.current.startOfDay(for: entry.date)
            if entryDay == checkDate {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate)!
            } else if entryDay < checkDate {
                break
            }
        }

        currentStreak = streak
        longestStreak = max(longestStreak, streak)
        updatedAt = Date()
    }

    // MARK: - Init
    init(
        id: UUID = UUID(),
        name: String,
        habitDescription: String = "",
        category: HabitCategory = .other,
        emoji: String = "⭐",
        frequency: HabitFrequency = .daily,
        targetDaysOfWeek: [Int] = [],
        reminderTime: Date? = nil,
        dailyGoalCount: Int = 1,
        unit: String? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name
        self.habitDescription = habitDescription
        self.categoryRaw = category.rawValue
        self.emoji = emoji
        self.frequencyRaw = frequency.rawValue
        self.targetDaysOfWeek = targetDaysOfWeek
        self.reminderTime = reminderTime
        self.dailyGoalCount = dailyGoalCount
        self.unit = unit
        self.currentStreak = 0
        self.longestStreak = 0
        self.totalCompletions = 0
        self.startDate = Date()
        self.isArchived = false
        self.isPaused = false
    }
}
