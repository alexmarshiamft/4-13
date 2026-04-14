// FocusSession.swift – SwiftData model for a Pomodoro-style focus session
// Lumina: AI-powered reminders, task management, and focus app

import Foundation
import SwiftData

// MARK: - Session Phase
enum FocusPhase: String, Codable, CaseIterable {
    case work       = "work"        // active focus work block
    case shortBreak = "short_break" // 5-minute break
    case longBreak  = "long_break"  // 15-minute break (every 4 pomodoros)
}

// MARK: - Session Status
enum FocusSessionStatus: String, Codable {
    case active     = "active"
    case paused     = "paused"
    case completed  = "completed"
    case abandoned  = "abandoned"
}

// MARK: - FocusSession SwiftData Model
@Model
final class FocusSession {

    // ── Identity ──────────────────────────────────────────────────────────────
    var id: UUID
    var createdAt: Date

    // ── Timing ────────────────────────────────────────────────────────────────
    var startTime: Date
    var endTime: Date?
    var plannedDurationSeconds: Int    // e.g. 25 * 60
    var actualDurationSeconds: Int     // updated as session progresses

    // ── Phase ─────────────────────────────────────────────────────────────────
    var phaseRaw: String
    var pomodoroCount: Int             // completed pomodoros in this session set

    // ── Status ────────────────────────────────────────────────────────────────
    var statusRaw: String

    // ── Content ───────────────────────────────────────────────────────────────
    var label: String                  // user label for the session e.g. "Deep Work"
    var linkedTaskIDs: [UUID]          // tasks being worked on

    // ── Focus Context ─────────────────────────────────────────────────────────
    var blockedWebsites: [String]      // domains blocked during this session
    var dndEnabled: Bool               // whether macOS DND was enabled

    // MARK: - Computed Properties

    var phase: FocusPhase {
        get { FocusPhase(rawValue: phaseRaw) ?? .work }
        set { phaseRaw = newValue.rawValue }
    }

    var sessionStatus: FocusSessionStatus {
        get { FocusSessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var elapsedSeconds: Int {
        let end = endTime ?? Date()
        return Int(end.timeIntervalSince(startTime))
    }

    var remainingSeconds: Int {
        max(0, plannedDurationSeconds - actualDurationSeconds)
    }

    var completionFraction: Double {
        guard plannedDurationSeconds > 0 else { return 0 }
        return min(Double(actualDurationSeconds) / Double(plannedDurationSeconds), 1.0)
    }

    // MARK: - Init
    init(
        id: UUID = UUID(),
        label: String = "Focus Session",
        phase: FocusPhase = .work,
        plannedDurationSeconds: Int = 25 * 60,
        linkedTaskIDs: [UUID] = [],
        blockedWebsites: [String] = [],
        dndEnabled: Bool = true
    ) {
        self.id = id
        self.createdAt = Date()
        self.startTime = Date()
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = 0
        self.phaseRaw = phase.rawValue
        self.statusRaw = FocusSessionStatus.active.rawValue
        self.pomodoroCount = 0
        self.label = label
        self.linkedTaskIDs = linkedTaskIDs
        self.blockedWebsites = blockedWebsites
        self.dndEnabled = dndEnabled
    }

    // MARK: - Helpers
    func complete() {
        endTime = Date()
        sessionStatus = .completed
        if phase == .work { pomodoroCount += 1 }
    }

    func abandon() {
        endTime = Date()
        sessionStatus = .abandoned
    }

    func pause() {
        sessionStatus = .paused
    }

    func resume() {
        sessionStatus = .active
    }

    func tick(by seconds: Int = 1) {
        actualDurationSeconds = min(actualDurationSeconds + seconds, plannedDurationSeconds)
    }
}
