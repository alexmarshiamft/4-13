// CalendarSyncManager.swift – EventKit two-way calendar sync & conflict resolution
// Lumina: AI-powered reminders, task management, and focus app
//
// Module D: Auto-Rescheduling & Calendar Sync
//  - Two-way sync with Apple Calendar
//  - Background conflict detection
//  - Auto-suggest next free time block for conflicting tasks

import Foundation
#if canImport(EventKit)
import EventKit
#endif
import SwiftData

// MARK: - Conflict
struct CalendarConflict: Identifiable {
    let id = UUID()
    let task: LuminaTask
    let conflictingEvent: String   // event title
    let eventStart: Date
    let eventEnd: Date
    let suggestedRescheduleDate: Date?
}

// MARK: - CalendarSyncManager
@MainActor
final class CalendarSyncManager: ObservableObject {

#if canImport(EventKit)
    private let eventStore = EKEventStore()
#endif

    @Published var isAuthorized = false
    @Published var detectedConflicts: [CalendarConflict] = []
    @Published var isSyncing = false

    // MARK: - Init
    init() {
        Task { await checkAuthorization() }
    }

    // MARK: - Authorization
    func requestAccess() async {
#if canImport(EventKit)
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            if granted { await performInitialSync() }
        } catch {
            print("[Lumina] Calendar access error: \(error)")
        }
#endif
    }

    private func checkAuthorization() async {
#if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess || status == .authorized)
#endif
    }

    // MARK: - Create Calendar Event for Task
    /// Creates an EKEvent in the user's default calendar and stores the identifier on the task.
    func createEvent(for task: LuminaTask) async {
#if canImport(EventKit)
        guard isAuthorized, let calendar = eventStore.defaultCalendarForNewEvents else { return }

        let event = EKEvent(eventStore: eventStore)
        event.title = task.title
        event.notes = task.notes
        event.calendar = calendar

        if let start = task.effectiveDueDate {
            event.startDate = start
            event.endDate = start.addingTimeInterval(3600)  // default 1-hour block
        } else {
            event.isAllDay = true
            event.startDate = task.dueDate ?? Date()
            event.endDate = event.startDate
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            task.calendarEventIdentifier = event.eventIdentifier
        } catch {
            print("[Lumina] Failed to create calendar event: \(error)")
        }
#endif
    }

    // MARK: - Update Calendar Event for Task
    func updateEvent(for task: LuminaTask) async {
#if canImport(EventKit)
        guard isAuthorized,
              let identifier = task.calendarEventIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else {
            await createEvent(for: task)
            return
        }

        event.title = task.title
        event.notes = task.notes
        if let start = task.effectiveDueDate {
            event.startDate = start
            event.endDate = start.addingTimeInterval(3600)
        }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("[Lumina] Failed to update calendar event: \(error)")
        }
#endif
    }

    // MARK: - Delete Calendar Event
    func deleteEvent(for task: LuminaTask) {
#if canImport(EventKit)
        guard isAuthorized,
              let identifier = task.calendarEventIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            print("[Lumina] Failed to delete calendar event: \(error)")
        }
#endif
    }

    // MARK: - Conflict Detection
    /// Scans a list of tasks to find any whose scheduled time overlaps a calendar event.
    func detectConflicts(in tasks: [LuminaTask]) async {
#if canImport(EventKit)
        guard isAuthorized else { return }
        isSyncing = true
        defer { isSyncing = false }

        var found: [CalendarConflict] = []

        for task in tasks where task.status == .pending {
            guard let taskDate = task.effectiveDueDate else { continue }
            let taskEnd = taskDate.addingTimeInterval(3600)

            let predicate = eventStore.predicateForEvents(
                withStart: taskDate.addingTimeInterval(-300),  // ±5 min buffer
                end: taskEnd.addingTimeInterval(300),
                calendars: nil
            )
            let events = eventStore.events(matching: predicate)

            for event in events where !event.isAllDay {
                // Skip the event that was created by this task itself
                if event.eventIdentifier == task.calendarEventIdentifier { continue }

                // Overlap: event starts before task ends AND event ends after task starts
                if event.startDate < taskEnd && event.endDate > taskDate {
                    let suggested = await findNextFreeBlock(after: event.endDate, duration: 3600)
                    found.append(CalendarConflict(
                        task: task,
                        conflictingEvent: event.title ?? "Untitled Event",
                        eventStart: event.startDate,
                        eventEnd: event.endDate,
                        suggestedRescheduleDate: suggested
                    ))
                }
            }
        }

        detectedConflicts = found
#endif
    }

    // MARK: - Find Next Free Block
    /// Finds the next calendar window of at least `duration` seconds, starting after `start`.
    func findNextFreeBlock(after start: Date, duration: TimeInterval) async -> Date? {
#if canImport(EventKit)
        guard isAuthorized else { return nil }

        let searchEnd = start.addingTimeInterval(7 * 24 * 3600)  // search up to 7 days ahead
        var candidate = roundUpToNextHalfHour(date: start)

        while candidate < searchEnd {
            let blockEnd = candidate.addingTimeInterval(duration)
            // Only check during working hours 8 AM – 7 PM
            let hour = Calendar.current.component(.hour, from: candidate)
            guard (8...19).contains(hour) else {
                candidate = nextMorning(after: candidate)
                continue
            }

            let predicate = eventStore.predicateForEvents(withStart: candidate, end: blockEnd, calendars: nil)
            let events = eventStore.events(matching: predicate)
            if events.isEmpty { return candidate }

            // Jump past the end of the latest overlapping event
            let latestEnd = events.map(\.endDate).max() ?? blockEnd
            candidate = latestEnd
        }
        return nil
#else
        return nil
#endif
    }

    // MARK: - Apply Suggested Reschedule (Bulk)
    func applyAllSuggestedReschedules() {
        for conflict in detectedConflicts {
            if let suggested = conflict.suggestedRescheduleDate {
                conflict.task.reschedule(to: suggested)
            }
        }
        detectedConflicts.removeAll()
    }

    // MARK: - Initial Sync
    private func performInitialSync() async {
#if canImport(EventKit)
        // Register for external calendar change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDatabaseChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
#endif
    }

#if canImport(EventKit)
    @objc private func calendarDatabaseChanged() {
        Task { @MainActor in
            // Trigger background sync when external calendar changes
            NotificationCenter.default.post(name: .luminaCalendarChanged, object: nil)
        }
    }
#endif

    // MARK: - Helpers
    private func roundUpToNextHalfHour(date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        if minute == 0 { return date }
        comps.minute = minute <= 30 ? 30 : 0
        if minute > 30 { comps.hour = (comps.hour ?? 0) + 1 }
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    private func nextMorning(after date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.day = (comps.day ?? 0) + 1
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? date
    }
}

extension Notification.Name {
    static let luminaCalendarChanged = Notification.Name("luminaCalendarChanged")
}
