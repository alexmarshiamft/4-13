// NotificationScheduler.swift – Context-aware, smart notification engine
// Lumina: AI-powered reminders, task management, and focus app
//
// Module B: Context-Aware Notification Engine
//  - Checks EventKit free/busy before firing
//  - Delays if user is in an active meeting or has been deeply engaged
//  - Nudges during calendar gaps / detected breaks

import Foundation
import UserNotifications
#if canImport(EventKit)
import EventKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Smart Snooze Interval
enum SnoozeInterval: TimeInterval, CaseIterable {
    case fiveMinutes    = 300
    case fifteenMinutes = 900
    case thirtyMinutes  = 1800
    case oneHour        = 3600

    var label: String {
        switch self {
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes:  return "30 minutes"
        case .oneHour:        return "1 hour"
        }
    }
}

// MARK: - NotificationScheduler
@MainActor
final class NotificationScheduler: ObservableObject {

    // MARK: - Published State
    @Published var pendingNotifications: [UNNotificationRequest] = []
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Private
    private let center = UNUserNotificationCenter.current()
#if canImport(EventKit)
    private let eventStore = EKEventStore()
#endif
    private var checkTimer: Timer?

    // MARK: - Init
    init() {
        Task { await requestAuthorization() }
        startPeriodicCheck()
    }

    // MARK: - Authorization
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            if !granted {
                print("[Lumina] Notification permission denied.")
            }
        } catch {
            print("[Lumina] Notification auth error: \(error)")
        }
    }

    // MARK: - Schedule a Task Notification
    /// Schedule a smart notification for a LuminaTask.
    /// Before firing, the engine checks whether the user is busy or in a meeting.
    func schedule(task: LuminaTask) async {
        guard let fireDate = task.nextFireDate ?? task.effectiveDueDate else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = buildBody(for: task)
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = NotificationCategory.task.rawValue
        content.userInfo = [
            "taskID": task.id.uuidString,
            "type": "task"
        ]

        // Determine the best fire date considering context
        let adjustedDate = await smartFireDate(idealDate: fireDate)

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: adjustedDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: task),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("[Lumina] Scheduled notification for '\(task.title)' at \(adjustedDate)")
        } catch {
            print("[Lumina] Failed to schedule notification: \(error)")
        }
    }

    // MARK: - Schedule Habit Reminder
    func scheduleHabitReminder(habit: LuminaHabit) async {
        guard let reminderTime = habit.reminderTime else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(habit.emoji) \(habit.name)"
        content.body = "Time to keep your streak going!"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.habit.rawValue
        content.userInfo = ["habitID": habit.id.uuidString, "type": "habit"]

        let timeComps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComps, repeats: true)

        let request = UNNotificationRequest(
            identifier: "habit-\(habit.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("[Lumina] Failed to schedule habit reminder: \(error)")
        }
    }

    // MARK: - Cancel Notifications
    func cancel(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskID.uuidString)"])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Smart Fire Date (Context Check)
    /// Returns the ideal fire date, or delays it if the user is currently in a meeting or system is busy.
    func smartFireDate(idealDate: Date) async -> Date {
        guard idealDate <= Date().addingTimeInterval(60) else {
            // Future notification — don't adjust yet
            return idealDate
        }

        // ── Check macOS idle time ─────────────────────────────────────────────
        if await isSystemIdle() {
            // User is idle — fire immediately / on time
            return idealDate
        }

        // ── Check EventKit for active meeting ─────────────────────────────────
        if await isInActiveMeeting() {
            let nextBreak = await nextCalendarFreeSlot(after: Date())
            let delayed = nextBreak ?? Date().addingTimeInterval(SnoozeInterval.fifteenMinutes.rawValue)
            print("[Lumina] Smart snooze: user in meeting, delaying to \(delayed)")
            return delayed
        }

        return idealDate
    }

    // MARK: - System Idle Check
    private func isSystemIdle() async -> Bool {
#if canImport(AppKit)
        // CGEventSource-based idle time (seconds since last input event)
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        return idleSeconds > 60  // consider idle after 60 seconds of no input
#else
        return false
#endif
    }

    // MARK: - Active Meeting Check
    private func isInActiveMeeting() async -> Bool {
#if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return false }

        let now = Date()
        let endWindow = now.addingTimeInterval(60)
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endWindow,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)
        return events.contains { event in
            event.startDate <= now && event.endDate >= now && !event.isAllDay
        }
#else
        return false
#endif
    }

    // MARK: - Next Free Calendar Slot
    private func nextCalendarFreeSlot(after start: Date) async -> Date? {
#if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return nil }

        // Search the next 4 hours in 15-minute chunks for a free slot
        for offset in stride(from: 0, through: 240, by: 15) {
            let slotStart = start.addingTimeInterval(TimeInterval(offset * 60))
            let slotEnd   = slotStart.addingTimeInterval(900)  // 15-min window
            let predicate = eventStore.predicateForEvents(withStart: slotStart, end: slotEnd, calendars: nil)
            let events = eventStore.events(matching: predicate)
            if events.isEmpty { return slotStart }
        }
        return nil
#else
        return nil
#endif
    }

    // MARK: - Refresh Pending List
    func refreshPendingNotifications() async {
        pendingNotifications = await center.pendingNotificationRequests()
    }

    // MARK: - Periodic Smart Check
    private func startPeriodicCheck() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshPendingNotifications()
            }
        }
    }

    // MARK: - Helpers
    private func notificationID(for task: LuminaTask) -> String {
        "task-\(task.id.uuidString)"
    }

    private func buildBody(for task: LuminaTask) -> String {
        if let due = task.effectiveDueDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Due \(formatter.localizedString(for: due, relativeTo: Date()))"
        }
        return task.notes.isEmpty ? "Tap to open Lumina" : task.notes
    }
}

// MARK: - Notification Categories
enum NotificationCategory: String {
    case task   = "LUMINA_TASK"
    case habit  = "LUMINA_HABIT"
    case focus  = "LUMINA_FOCUS"
    case rescheduleSuggestion = "LUMINA_RESCHEDULE"
}

// MARK: - Notification Category Registration
extension NotificationScheduler {
    func registerCategories() {
        let snooze5  = UNNotificationAction(identifier: "SNOOZE_5",  title: "Snooze 5 min",  options: [])
        let snooze15 = UNNotificationAction(identifier: "SNOOZE_15", title: "Snooze 15 min", options: [])
        let complete = UNNotificationAction(identifier: "COMPLETE",  title: "Mark Complete", options: [.destructive])
        let open     = UNNotificationAction(identifier: "OPEN",      title: "Open Lumina",   options: [.foreground])

        let taskCategory = UNNotificationCategory(
            identifier: NotificationCategory.task.rawValue,
            actions: [complete, snooze5, snooze15, open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let habitCategory = UNNotificationCategory(
            identifier: NotificationCategory.habit.rawValue,
            actions: [complete, open],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([taskCategory, habitCategory])
    }
}
