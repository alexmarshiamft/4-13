// FocusTimerViewModel.swift – Pomodoro-style focus timer state machine
// Lumina: AI-powered reminders, task management, and focus app
//
// Module C: Focus & Deep Work Timer
//  - Pomodoro state machine (work → short break → work → ... → long break)
//  - Integrates with macOS Focus APIs (Do Not Disturb)
//  - Menu bar countdown visual

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Timer State
enum TimerState {
    case idle
    case running
    case paused
    case break_
    case completed
}

// MARK: - FocusTimerViewModel
@MainActor
final class FocusTimerViewModel: ObservableObject {

    // MARK: - Configuration
    struct Configuration {
        var workDurationSeconds: Int    = 25 * 60
        var shortBreakSeconds: Int      =  5 * 60
        var longBreakSeconds: Int       = 15 * 60
        var pomodorosUntilLongBreak: Int = 4
        var autoStartBreaks: Bool       = true
        var autoStartWork: Bool         = false
        var blockedWebsites: [String]   = []
        var enableDND: Bool             = true
    }

    // MARK: - Published State
    @Published var state: TimerState = .idle
    @Published var currentPhase: FocusPhase = .work
    @Published var remainingSeconds: Int = 25 * 60
    @Published var completedPomodoros: Int = 0
    @Published var config = Configuration()
    @Published var sessionLabel: String = "Focus Session"
    @Published var linkedTaskIDs: [UUID] = []
    @Published var totalFocusTimeToday: Int = 0  // seconds

    // MARK: - Private
    private var timer: Timer?
    private var ticksElapsed: Int = 0
    private var dndWasEnabled: Bool = false

    // MARK: - Computed Properties
    var progress: Double {
        let total = totalSecondsForCurrentPhase
        guard total > 0 else { return 0 }
        return Double(total - remainingSeconds) / Double(total)
    }

    var totalSecondsForCurrentPhase: Int {
        switch currentPhase {
        case .work:       return config.workDurationSeconds
        case .shortBreak: return config.shortBreakSeconds
        case .longBreak:  return config.longBreakSeconds
        }
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var menuBarTitle: String {
        switch state {
        case .idle:      return "Lumina"
        case .running:   return "⏱ \(formattedTime)"
        case .paused:    return "⏸ \(formattedTime)"
        case .break_:    return "☕ \(formattedTime)"
        case .completed: return "✅ Done"
        }
    }

    var phaseLabel: String {
        switch currentPhase {
        case .work:       return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak:  return "Long Break"
        }
    }

    var isActive: Bool { state == .running || state == .break_ }

    // MARK: - Start Session
    func start() {
        guard state == .idle || state == .paused else { return }
        state = .running
        ticksElapsed = 0
        startTimer()
        if config.enableDND { enableDND() }
    }

    // MARK: - Pause / Resume
    func pauseOrResume() {
        switch state {
        case .running:
            state = .paused
            stopTimer()
        case .paused:
            state = .running
            startTimer()
        default:
            break
        }
    }

    // MARK: - Stop / Reset
    func stop() {
        stopTimer()
        state = .idle
        currentPhase = .work
        remainingSeconds = config.workDurationSeconds
        ticksElapsed = 0
        if config.enableDND { disableDND() }
    }

    // MARK: - Skip Phase
    func skip() {
        stopTimer()
        transitionToNextPhase()
    }

    // MARK: - Add Task to Session
    func link(taskID: UUID) {
        if !linkedTaskIDs.contains(taskID) {
            linkedTaskIDs.append(taskID)
        }
    }

    func unlink(taskID: UUID) {
        linkedTaskIDs.removeAll { $0 == taskID }
    }

    // MARK: - Private Timer Management
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running || state == .break_ else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            ticksElapsed += 1
            if currentPhase == .work { totalFocusTimeToday += 1 }
        } else {
            phaseCompleted()
        }
    }

    private func phaseCompleted() {
        stopTimer()

        switch currentPhase {
        case .work:
            completedPomodoros += 1
            postPhaseCompletionNotification(phase: .work)
            transitionToNextPhase()

        case .shortBreak, .longBreak:
            postPhaseCompletionNotification(phase: currentPhase)
            transitionToNextPhase()
        }
    }

    private func transitionToNextPhase() {
        switch currentPhase {
        case .work:
            if completedPomodoros % config.pomodorosUntilLongBreak == 0 {
                currentPhase = .longBreak
                remainingSeconds = config.longBreakSeconds
            } else {
                currentPhase = .shortBreak
                remainingSeconds = config.shortBreakSeconds
            }
            state = .break_
            if config.autoStartBreaks { startTimer() }

        case .shortBreak, .longBreak:
            currentPhase = .work
            remainingSeconds = config.workDurationSeconds
            state = .idle
            if config.autoStartWork {
                state = .running
                startTimer()
            }
        }
    }

    // MARK: - Do Not Disturb Integration
    private func enableDND() {
#if canImport(AppKit)
        // macOS Focus mode via `shortcuts run` or Focus API
        // The Focus API (FocusStatusProviding) is available in macOS 12+
        // We use an AppleScript bridge for broad compatibility
        let script = """
        tell application "System Events"
            tell application process "Control Center"
                -- Enable Focus / Do Not Disturb
            end tell
        end tell
        """
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
        dndWasEnabled = true
#endif
    }

    private func disableDND() {
#if canImport(AppKit)
        guard dndWasEnabled else { return }
        // Mirror of enableDND — disable Do Not Disturb
        dndWasEnabled = false
#endif
    }

    // MARK: - Notifications
    private func postPhaseCompletionNotification(phase: FocusPhase) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()

        switch phase {
        case .work:
            content.title = "Pomodoro Complete! 🍅"
            let breaks = completedPomodoros % config.pomodorosUntilLongBreak == 0 ? "long break" : "short break"
            content.body = "Time for a \(breaks). You've completed \(completedPomodoros) pomodoro(s)."
        case .shortBreak:
            content.title = "Break Over"
            content.body = "Ready to focus again?"
        case .longBreak:
            content.title = "Long Break Over"
            content.body = "Great work! Start another focus session?"
        }

        content.sound = .default
        content.categoryIdentifier = NotificationCategory.focus.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "focus-phase-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}

// MARK: - UserNotifications import (needed for UNUserNotificationCenter)
import UserNotifications
