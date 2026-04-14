// LuminaTests.swift – Unit tests for core Lumina logic (NLP, models, recurrence engine)
// These tests validate platform-agnostic logic and don't require macOS frameworks.

import XCTest
@testable import Lumina

// MARK: - NLP Parser Tests
final class NLPParserTests: XCTestCase {

    var parser: NLPParser!

    override func setUp() {
        super.setUp()
        parser = NLPParser.shared
    }

    // MARK: - Title Extraction
    func testSimpleTitleExtraction() {
        let result = parser.parse("Buy groceries")
        XCTAssertEqual(result.title, "Buy groceries")
        XCTAssertNil(result.dueDate)
        XCTAssertEqual(result.priority, .none)
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testTitleCapitalization() {
        let result = parser.parse("call dentist")
        XCTAssertEqual(result.title.first?.isUppercase, true, "Title should start with uppercase")
    }

    // MARK: - Date Extraction
    func testTodayDate() {
        let result = parser.parse("Submit report today")
        XCTAssertNotNil(result.dueDate)
        if let date = result.dueDate {
            XCTAssertTrue(Calendar.current.isDateInToday(date))
        }
    }

    func testTomorrowDate() {
        let result = parser.parse("Call dentist tomorrow")
        XCTAssertNotNil(result.dueDate)
        if let date = result.dueDate {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            XCTAssertTrue(Calendar.current.isDate(date, inSameDayAs: tomorrow))
        }
    }

    func testRelativeWeekday() {
        let result = parser.parse("Team meeting next Friday")
        XCTAssertNotNil(result.dueDate)
        if let date = result.dueDate {
            let weekday = Calendar.current.component(.weekday, from: date)
            XCTAssertEqual(weekday, 6, "Next Friday should be weekday 6")
        }
    }

    // MARK: - Time Extraction
    func testAmPmTime() {
        let result = parser.parse("Doctor appointment at 2 PM")
        XCTAssertNotNil(result.dueTime)
        if let time = result.dueTime {
            let hour = Calendar.current.component(.hour, from: time)
            XCTAssertEqual(hour, 14)
        }
    }

    func testMorningTime() {
        let result = parser.parse("Morning run at 6:30 AM")
        XCTAssertNotNil(result.dueTime)
        if let time = result.dueTime {
            let hour = Calendar.current.component(.hour, from: time)
            let minute = Calendar.current.component(.minute, from: time)
            XCTAssertEqual(hour, 6)
            XCTAssertEqual(minute, 30)
        }
    }

    func testNoonTime() {
        let result = parser.parse("Lunch at 12 PM")
        XCTAssertNotNil(result.dueTime)
        if let time = result.dueTime {
            let hour = Calendar.current.component(.hour, from: time)
            XCTAssertEqual(hour, 12)
        }
    }

    // MARK: - Priority Extraction
    func testUrgentPriority() {
        let result = parser.parse("Fix production bug urgent")
        XCTAssertEqual(result.priority, .urgent)
    }

    func testHighPriority() {
        let result = parser.parse("Review PR high importance")
        XCTAssertEqual(result.priority, .high)
    }

    func testLowPriority() {
        let result = parser.parse("Clean desk someday")
        XCTAssertEqual(result.priority, .low)
    }

    // MARK: - Tag Extraction
    func testSingleTag() {
        let result = parser.parse("Workout #fitness")
        XCTAssertEqual(result.tags, ["fitness"])
    }

    func testMultipleTags() {
        let result = parser.parse("Read chapter 3 #books #learning")
        XCTAssertTrue(result.tags.contains("books"))
        XCTAssertTrue(result.tags.contains("learning"))
        XCTAssertEqual(result.tags.count, 2)
    }

    func testTagsRemovedFromTitle() {
        let result = parser.parse("Buy groceries #errands")
        XCTAssertFalse(result.title.contains("#"), "Tags should be removed from title")
    }

    // MARK: - Recurrence Extraction
    func testDailyRecurrence() {
        let result = parser.parse("Meditate daily")
        XCTAssertTrue(result.isRecurring)
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
    }

    func testEveryNDaysRecurrence() {
        let result = parser.parse("Water plants every 3 days")
        XCTAssertTrue(result.isRecurring)
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
    }

    func testWeeklyRecurrence() {
        let result = parser.parse("Team standup every Monday")
        XCTAssertTrue(result.isRecurring)
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertTrue(result.recurrenceRule?.daysOfWeek?.contains(2) ?? false, "Monday = 2")
    }

    func testMonthlyNthWeekdayRecurrence() {
        let result = parser.parse("Board meeting every 3rd Friday")
        XCTAssertTrue(result.isRecurring)
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.weekOfMonth, 3)
        XCTAssertTrue(result.recurrenceRule?.daysOfWeek?.contains(6) ?? false, "Friday = 6")
    }

    func testEveryMonthRecurrence() {
        let result = parser.parse("Pay rent every month")
        XCTAssertTrue(result.isRecurring)
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
    }

    // MARK: - Combined Parsing
    func testFullSentenceParsing() {
        // "Review design files before tomorrow's 10 AM sync"
        let result = parser.parse("Review design files before tomorrow at 10 AM #work")
        XCTAssertFalse(result.title.isEmpty)
        XCTAssertNotNil(result.dueDate)
        XCTAssertNotNil(result.dueTime)
        if let time = result.dueTime {
            let hour = Calendar.current.component(.hour, from: time)
            XCTAssertEqual(hour, 10)
        }
        XCTAssertTrue(result.tags.contains("work"))
    }

    func testPriorityTagsAndDate() {
        let result = parser.parse("Submit tax return by tomorrow urgent #finance")
        XCTAssertEqual(result.priority, .urgent)
        XCTAssertTrue(result.tags.contains("finance"))
        XCTAssertNotNil(result.dueDate)
    }

    // MARK: - Confidence Score
    func testConfidenceIncreasesWithData() {
        let simple = parser.parse("Buy milk")
        let rich   = parser.parse("Buy milk tomorrow at 10 AM #errands urgent")
        XCTAssertGreaterThan(rich.confidence, simple.confidence)
    }

    func testEmptyInput() {
        let result = parser.parse("")
        XCTAssertEqual(result.title, "")
    }
}

// MARK: - RecurrenceRule Tests
final class RecurrenceRuleTests: XCTestCase {

    func testDailyDisplayString() {
        let rule = RecurrenceRule(frequency: .daily, interval: 1)
        XCTAssertEqual(rule.displayString, "Every day")
    }

    func testEveryNDaysDisplayString() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        XCTAssertEqual(rule.displayString, "Every 3 days")
    }

    func testMonthlyOrdinalDisplayString() {
        var rule = RecurrenceRule(frequency: .monthly, interval: 1)
        rule.daysOfWeek = [6]  // Friday
        rule.weekOfMonth = 3
        XCTAssertTrue(rule.displayString.contains("3rd"))
        XCTAssertTrue(rule.displayString.lowercased().contains("friday"))
    }
}

// MARK: - LuminaTask Model Tests
final class LuminaTaskModelTests: XCTestCase {

    func testTaskIsOverdueWhenPastDue() {
        let task = LuminaTask(
            title: "Past due task",
            dueDate: Date().addingTimeInterval(-3600)
        )
        XCTAssertTrue(task.isOverdue)
    }

    func testTaskNotOverdueWhenCompleted() {
        let task = LuminaTask(
            title: "Done task",
            dueDate: Date().addingTimeInterval(-3600)
        )
        task.status = .completed
        XCTAssertFalse(task.isOverdue)
    }

    func testSnoozeIncrementsCount() {
        let task = LuminaTask(title: "Snoozed task")
        task.snooze(by: 900)
        XCTAssertEqual(task.snoozeCount, 1)
        XCTAssertEqual(task.status, .snoozed)
        XCTAssertNotNil(task.nextFireDate)
    }

    func testMarkCompleted() {
        let task = LuminaTask(title: "Completed task")
        task.markCompleted()
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.status, .completed)
    }

    func testReschedule() {
        let task = LuminaTask(title: "Rescheduled task")
        task.status = .snoozed
        let newDate = Date().addingTimeInterval(3600)
        task.reschedule(to: newDate)
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.scheduledDate, newDate)
    }

    func testEffectiveDueDateCombinesDateAndTime() {
        var dateComps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComps.hour = 0; dateComps.minute = 0
        let dueDate = Calendar.current.date(from: dateComps)!

        var timeComps = DateComponents()
        timeComps.hour = 14; timeComps.minute = 30
        let dueTime = Calendar.current.date(from: timeComps)!

        let task = LuminaTask(title: "Meeting", dueDate: dueDate, dueTime: dueTime)
        let effective = task.effectiveDueDate
        XCTAssertNotNil(effective)
        if let eff = effective {
            XCTAssertEqual(Calendar.current.component(.hour, from: eff), 14)
            XCTAssertEqual(Calendar.current.component(.minute, from: eff), 30)
        }
    }

    func testPriorityRoundTrips() {
        for priority in TaskPriority.allCases {
            let task = LuminaTask(title: "Test", priority: priority)
            XCTAssertEqual(task.priority, priority)
            XCTAssertEqual(task.priorityRaw, priority.rawValue)
        }
    }
}

// MARK: - LuminaHabit Model Tests
final class LuminaHabitModelTests: XCTestCase {

    func testInitialStreak() {
        let habit = LuminaHabit(name: "Meditation")
        XCTAssertEqual(habit.currentStreak, 0)
        XCTAssertEqual(habit.longestStreak, 0)
        XCTAssertFalse(habit.isCompletedToday)
    }

    func testIsScheduledOnWeekdays() {
        let habit = LuminaHabit(name: "Work habit", frequency: .weekdays)
        // Test a Monday
        var comps = DateComponents(); comps.weekday = 2; comps.weekOfYear = 1; comps.year = 2025
        let monday = Calendar.current.date(from: comps)!
        XCTAssertTrue(habit.isScheduled(on: monday))
        // Test a Saturday
        comps.weekday = 7
        let saturday = Calendar.current.date(from: comps)!
        XCTAssertFalse(habit.isScheduled(on: saturday))
    }

    func testIsScheduledOnWeekends() {
        let habit = LuminaHabit(name: "Weekend run", frequency: .weekends)
        var comps = DateComponents(); comps.weekday = 7; comps.weekOfYear = 1; comps.year = 2025
        let saturday = Calendar.current.date(from: comps)!
        XCTAssertTrue(habit.isScheduled(on: saturday))
        comps.weekday = 2
        let monday = Calendar.current.date(from: comps)!
        XCTAssertFalse(habit.isScheduled(on: monday))
    }

    func testCompletionRate30DaysEmpty() {
        let habit = LuminaHabit(name: "New habit")
        XCTAssertEqual(habit.completionRate30Days, 0.0)
    }

    func testCategoryRoundTrip() {
        for cat in HabitCategory.allCases {
            let habit = LuminaHabit(name: "Test", category: cat)
            XCTAssertEqual(habit.category, cat)
        }
    }
}

// MARK: - HabitEntry Tests
final class HabitEntryTests: XCTestCase {

    func testIncrementIncreases() {
        let entry = HabitEntry(completionCount: 0, goalCount: 3)
        entry.increment()
        XCTAssertEqual(entry.completionCount, 1)
        XCTAssertFalse(entry.isCompleted)
    }

    func testIncrementToCompletion() {
        let entry = HabitEntry(completionCount: 2, goalCount: 3)
        entry.increment()
        XCTAssertTrue(entry.isCompleted)
        XCTAssertNotNil(entry.completedAt)
    }

    func testDecrementDecreases() {
        let entry = HabitEntry(completionCount: 2, goalCount: 3)
        entry.decrement()
        XCTAssertEqual(entry.completionCount, 1)
    }

    func testDecrementDoesNotGoNegative() {
        let entry = HabitEntry(completionCount: 0, goalCount: 3)
        entry.decrement()
        XCTAssertEqual(entry.completionCount, 0)
    }

    func testReset() {
        let entry = HabitEntry(completionCount: 3, goalCount: 3)
        entry.completedAt = Date()
        entry.reset()
        XCTAssertEqual(entry.completionCount, 0)
        XCTAssertNil(entry.completedAt)
    }

    func testCompletionFraction() {
        let entry = HabitEntry(completionCount: 2, goalCount: 4)
        XCTAssertEqual(entry.completionFraction, 0.5, accuracy: 0.001)
    }

    func testCompletionFractionCapsAtOne() {
        let entry = HabitEntry(completionCount: 5, goalCount: 3)
        XCTAssertEqual(entry.completionFraction, 1.0, accuracy: 0.001)
    }
}

// MARK: - FocusSession Tests
final class FocusSessionTests: XCTestCase {

    func testInitialState() {
        let session = FocusSession(label: "Test", phase: .work, plannedDurationSeconds: 1500)
        XCTAssertEqual(session.phase, .work)
        XCTAssertEqual(session.actualDurationSeconds, 0)
        XCTAssertEqual(session.plannedDurationSeconds, 1500)
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.remainingSeconds, 1500)
    }

    func testTick() {
        let session = FocusSession(plannedDurationSeconds: 60)
        session.tick(by: 10)
        XCTAssertEqual(session.actualDurationSeconds, 10)
        XCTAssertEqual(session.remainingSeconds, 50)
    }

    func testTickDoesNotExceedPlanned() {
        let session = FocusSession(plannedDurationSeconds: 60)
        session.tick(by: 100)
        XCTAssertEqual(session.actualDurationSeconds, 60)
        XCTAssertEqual(session.remainingSeconds, 0)
    }

    func testComplete() {
        let session = FocusSession(phase: .work, plannedDurationSeconds: 60)
        session.complete()
        XCTAssertEqual(session.sessionStatus, .completed)
        XCTAssertNotNil(session.endTime)
        XCTAssertEqual(session.pomodoroCount, 1)
    }

    func testAbandon() {
        let session = FocusSession()
        session.abandon()
        XCTAssertEqual(session.sessionStatus, .abandoned)
        XCTAssertNotNil(session.endTime)
    }

    func testCompletionFraction() {
        let session = FocusSession(plannedDurationSeconds: 100)
        session.tick(by: 75)
        XCTAssertEqual(session.completionFraction, 0.75, accuracy: 0.001)
    }

    func testPauseAndResume() {
        let session = FocusSession()
        session.pause()
        XCTAssertEqual(session.sessionStatus, .paused)
        session.resume()
        XCTAssertEqual(session.sessionStatus, .active)
    }
}

// MARK: - ThemeManager Tests
final class ThemeManagerTests: XCTestCase {

    func testDefaultTheme() {
        UserDefaults.standard.removeObject(forKey: "lumina.theme")
        let manager = ThemeManager()
        XCTAssertEqual(manager.currentTheme, .system)
    }

    func testThemePersistence() {
        let manager = ThemeManager()
        manager.currentTheme = .deepSpaceDark
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lumina.theme"), "deep_space_dark")
    }

    func testColorSchemeForDarkTheme() {
        let manager = ThemeManager()
        manager.currentTheme = .deepSpaceDark
        XCTAssertEqual(manager.colorScheme, .dark)
    }

    func testColorSchemeForLightTheme() {
        let manager = ThemeManager()
        manager.currentTheme = .minimalistLight
        XCTAssertEqual(manager.colorScheme, .light)
    }

    func testColorSchemeForSystemTheme() {
        let manager = ThemeManager()
        manager.currentTheme = .system
        XCTAssertNil(manager.colorScheme)
    }

    func testDeepSpaceDarkPalette() {
        let manager = ThemeManager()
        manager.currentTheme = .deepSpaceDark
        // Just verify the palette is not a default uninitialised value
        XCTAssertNotNil(manager.palette.accent)
    }

    func testAllThemesHaveDisplayName() {
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }
}

// MARK: - Color Hex Tests
final class ColorHexTests: XCTestCase {

    func testHexColorCreation() {
        // Simply check that Color(hex:) doesn't crash
        let _ = Color(hex: "#7C5CBF")
        let _ = Color(hex: "7C5CBF")
        let _ = Color(hex: "#ABC")
        let _ = Color(hex: "FF7C5CBF")
    }
}
