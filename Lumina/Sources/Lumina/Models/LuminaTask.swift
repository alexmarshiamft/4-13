// LuminaTask.swift – SwiftData model for a task/reminder
// Lumina: AI-powered reminders, task management, and focus app

import Foundation
import SwiftData

// MARK: - Task Priority
enum TaskPriority: Int, Codable, CaseIterable {
    case none   = 0
    case low    = 1
    case medium = 2
    case high   = 3
    case urgent = 4

    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var systemImage: String {
        switch self {
        case .none:   return "minus.circle"
        case .low:    return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high:   return "arrow.up.circle"
        case .urgent: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Task Status
enum TaskStatus: String, Codable, CaseIterable {
    case pending    = "pending"
    case inProgress = "in_progress"
    case completed  = "completed"
    case cancelled  = "cancelled"
    case snoozed    = "snoozed"
}

// MARK: - Trigger Type (for context-aware triggers)
enum TriggerType: String, Codable {
    case dateTime  = "date_time"
    case location  = "location"
    case wifi      = "wifi"
    case manual    = "manual"
    case calendar  = "calendar"
}

// MARK: - LuminaTask SwiftData Model
@Model
final class LuminaTask {

    // ── Identity ──────────────────────────────────────────────────────────────
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // ── Content ───────────────────────────────────────────────────────────────
    var title: String
    var notes: String
    var rawInput: String         // original NLP input string

    // ── Scheduling ────────────────────────────────────────────────────────────
    var dueDate: Date?
    var dueTime: Date?           // time-of-day component
    var scheduledDate: Date?     // possibly rescheduled date

    // ── Priority & Status ─────────────────────────────────────────────────────
    var priorityRaw: Int
    var statusRaw: String

    // ── Context Triggers ──────────────────────────────────────────────────────
    var triggerTypeRaw: String
    var locationName: String?    // e.g. "Home"
    var latitude: Double?
    var longitude: Double?
    var triggerRadiusMeters: Double?
    var wifiSSID: String?

    // ── Calendar Integration ──────────────────────────────────────────────────
    var calendarEventIdentifier: String?  // EventKit event ID
    var associatedCalendarTitle: String?

    // ── Recurrence ────────────────────────────────────────────────────────────
    var isRecurring: Bool
    var recurrenceRuleData: Data?         // encoded RecurrenceRule

    // ── Smart Snooze ─────────────────────────────────────────────────────────
    var snoozeCount: Int
    var lastSnoozedAt: Date?
    var nextFireDate: Date?

    // ── Relationships ─────────────────────────────────────────────────────────
    @Relationship(deleteRule: .nullify, inverse: \LuminaHabit.tasks)
    var habit: LuminaHabit?

    // ── Tags ──────────────────────────────────────────────────────────────────
    var tags: [String]

    // MARK: - Computed Properties

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var triggerType: TriggerType {
        get { TriggerType(rawValue: triggerTypeRaw) ?? .manual }
        set { triggerTypeRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }

    var effectiveDueDate: Date? {
        guard let date = dueDate else { return scheduledDate }
        if let time = dueTime {
            return Calendar.current.date(
                bySettingHour: Calendar.current.component(.hour, from: time),
                minute: Calendar.current.component(.minute, from: time),
                second: 0,
                of: date
            )
        }
        return date
    }

    var isOverdue: Bool {
        guard let due = effectiveDueDate, status == .pending else { return false }
        return due < Date()
    }

    // MARK: - Init
    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        rawInput: String = "",
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: TaskPriority = .none,
        status: TaskStatus = .pending,
        triggerType: TriggerType = .manual,
        tags: [String] = [],
        isRecurring: Bool = false
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.title = title
        self.notes = notes
        self.rawInput = rawInput
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.triggerTypeRaw = triggerType.rawValue
        self.tags = tags
        self.isRecurring = isRecurring
        self.snoozeCount = 0
    }

    // MARK: - Helpers
    func markCompleted() {
        status = .completed
        updatedAt = Date()
    }

    func snooze(by interval: TimeInterval) {
        snoozeCount += 1
        lastSnoozedAt = Date()
        nextFireDate = Date().addingTimeInterval(interval)
        status = .snoozed
        updatedAt = Date()
    }

    func reschedule(to newDate: Date) {
        scheduledDate = newDate
        status = .pending
        updatedAt = Date()
    }
}

// MARK: - RecurrenceRule (Codable value type stored as Data)
struct RecurrenceRule: Codable {
    enum Frequency: String, Codable {
        case daily, weekly, monthly, yearly, custom
    }

    var frequency: Frequency
    var interval: Int        // e.g. every N days/weeks/months
    var daysOfWeek: [Int]?   // 1=Sun … 7=Sat
    var weekOfMonth: Int?    // e.g. 3rd Friday → weekOfMonth=3
    var dayOfMonth: Int?     // specific day-of-month
    var monthOfYear: Int?    // specific month for yearly recurrence
    var endDate: Date?
    var occurrenceLimit: Int?

    // Human-readable description
    var displayString: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if let days = daysOfWeek, !days.isEmpty {
                let names = days.compactMap { Calendar.current.weekdaySymbols[safe: $0 - 1] }
                return "Every \(names.joined(separator: ", "))"
            }
            return interval == 1 ? "Every week" : "Every \(interval) weeks"
        case .monthly:
            if let week = weekOfMonth, let day = daysOfWeek?.first {
                let dayName = Calendar.current.weekdaySymbols[safe: day - 1] ?? ""
                let ordinal = ordinalString(for: week)
                return "Every \(ordinal) \(dayName)"
            }
            return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Every year" : "Every \(interval) years"
        case .custom:
            return "Custom recurrence"
        }
    }

    private func ordinalString(for n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
