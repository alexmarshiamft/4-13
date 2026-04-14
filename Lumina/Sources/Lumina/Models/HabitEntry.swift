// HabitEntry.swift – SwiftData model for a single habit completion record
// Lumina: AI-powered reminders, task management, and focus app

import Foundation
import SwiftData

// MARK: - HabitEntry SwiftData Model
/// Records each daily (or per-occurrence) attempt for a LuminaHabit.
/// Stores completion count, notes, and mood — enabling rich history/streak analytics.
@Model
final class HabitEntry {

    // ── Identity ──────────────────────────────────────────────────────────────
    var id: UUID
    var createdAt: Date

    // ── Timing ────────────────────────────────────────────────────────────────
    var date: Date          // calendar date of this entry (time zeroed to start-of-day)
    var completedAt: Date?  // exact timestamp when the last completion tap occurred

    // ── Completion ────────────────────────────────────────────────────────────
    var completionCount: Int   // how many times completed (vs dailyGoalCount)
    var goalCount: Int         // snapshot of the habit's goal at time of entry

    // ── Qualitative ───────────────────────────────────────────────────────────
    var notes: String
    var moodScore: Int?        // 1–5 subjective mood rating

    // ── Relationship ──────────────────────────────────────────────────────────
    var habit: LuminaHabit?

    // MARK: - Computed Properties

    var isCompleted: Bool { completionCount >= goalCount }

    var completionFraction: Double {
        guard goalCount > 0 else { return 0 }
        return min(Double(completionCount) / Double(goalCount), 1.0)
    }

    // MARK: - Init
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        completionCount: Int = 0,
        goalCount: Int = 1,
        notes: String = "",
        moodScore: Int? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.date = Calendar.current.startOfDay(for: date)
        self.completionCount = completionCount
        self.goalCount = goalCount
        self.notes = notes
        self.moodScore = moodScore
    }

    // MARK: - Helpers
    func increment() {
        if completionCount < goalCount {
            completionCount += 1
            if isCompleted { completedAt = Date() }
        }
    }

    func decrement() {
        if completionCount > 0 {
            completionCount -= 1
            if !isCompleted { completedAt = nil }
        }
    }

    func reset() {
        completionCount = 0
        completedAt = nil
    }
}
