// FocusTimerView.swift – Pomodoro focus timer UI with menu bar integration
// Lumina: AI-powered reminders, task management, and focus app
//
// Module C: Focus & Deep Work Timer

import SwiftUI
import SwiftData

// MARK: - FocusTimerView
struct FocusTimerView: View {

    // MARK: - Environment
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var focusTimerVM: FocusTimerViewModel
    @Environment(\.modelContext) private var modelContext

    // MARK: - Query
    @Query(filter: #Predicate<LuminaTask> { $0.statusRaw == "pending" })
    private var pendingTasks: [LuminaTask]

    // MARK: - State
    @State private var showSettings = false
    @State private var showWebsiteBlocker = false

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── Timer Ring ────────────────────────────────────────────────
                timerRingSection

                // ── Controls ──────────────────────────────────────────────────
                controlsSection

                // ── Pomodoro Progress ─────────────────────────────────────────
                pomodoroProgressSection

                // ── Session Tasks ─────────────────────────────────────────────
                if !pendingTasks.isEmpty {
                    sessionTasksSection
                }

                // ── Stats ─────────────────────────────────────────────────────
                todayStatsSection

                // ── Settings ──────────────────────────────────────────────────
                settingsSection
            }
            .padding(24)
        }
        .background(themeManager.palette.backgroundPrimary)
        .onReceive(NotificationCenter.default.publisher(for: .luminaStartFocus)) { _ in
            focusTimerVM.start()
        }
    }

    // MARK: - Timer Ring
    private var timerRingSection: some View {
        VStack(spacing: 16) {
            Text(focusTimerVM.phaseLabel.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(themeManager.palette.textTertiary)

            ZStack {
                // Outer ring background
                Circle()
                    .stroke(themeManager.palette.border, lineWidth: 12)

                // Progress arc
                Circle()
                    .trim(from: 0, to: focusTimerVM.progress)
                    .stroke(
                        phaseGradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: focusTimerVM.progress)

                // Center content
                VStack(spacing: 4) {
                    Text(focusTimerVM.formattedTime)
                        .font(.system(size: 52, weight: .thin, design: .monospaced))
                        .foregroundStyle(themeManager.palette.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.5), value: focusTimerVM.formattedTime)

                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(themeManager.palette.textSecondary)
                }
            }
            .frame(width: 220, height: 220)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls
    private var controlsSection: some View {
        HStack(spacing: 20) {
            // Stop / Reset
            if focusTimerVM.state != .idle {
                Button {
                    withAnimation { focusTimerVM.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(themeManager.palette.destructive)
                        .frame(width: 48, height: 48)
                        .background(themeManager.palette.destructive.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop session")
            }

            // Primary start/pause button
            Button {
                withAnimation(.spring(response: 0.4)) {
                    switch focusTimerVM.state {
                    case .idle:    focusTimerVM.start()
                    case .running, .break_: focusTimerVM.pauseOrResume()
                    case .paused:  focusTimerVM.pauseOrResume()
                    case .completed: focusTimerVM.stop()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(themeManager.accentGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: themeManager.palette.accent.opacity(0.4), radius: 12, x: 0, y: 4)

                    Image(systemName: primaryButtonIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            // Skip phase
            if focusTimerVM.state != .idle {
                Button {
                    withAnimation { focusTimerVM.skip() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(themeManager.palette.textSecondary)
                        .frame(width: 48, height: 48)
                        .background(themeManager.palette.backgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Skip to next phase")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pomodoro Progress Dots
    private var pomodoroProgressSection: some View {
        VStack(spacing: 8) {
            Text("\(focusTimerVM.completedPomodoros) Pomodoro\(focusTimerVM.completedPomodoros == 1 ? "" : "s") completed")
                .font(.caption)
                .foregroundStyle(themeManager.palette.textSecondary)

            HStack(spacing: 6) {
                ForEach(0..<focusTimerVM.config.pomodorosUntilLongBreak, id: \.self) { i in
                    Circle()
                        .fill(
                            i < (focusTimerVM.completedPomodoros % focusTimerVM.config.pomodorosUntilLongBreak)
                                ? themeManager.palette.accent
                                : themeManager.palette.border
                        )
                        .frame(width: 10, height: 10)
                        .animation(.spring(response: 0.3), value: focusTimerVM.completedPomodoros)
                }
                Image(systemName: "cup.and.saucer.fill")
                    .font(.caption)
                    .foregroundStyle(
                        focusTimerVM.completedPomodoros > 0 &&
                        focusTimerVM.completedPomodoros % focusTimerVM.config.pomodorosUntilLongBreak == 0
                            ? .orange
                            : themeManager.palette.border
                    )
            }
        }
    }

    // MARK: - Session Tasks
    private var sessionTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Linked Tasks")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.palette.textTertiary)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                ForEach(pendingTasks.prefix(5)) { task in
                    HStack(spacing: 10) {
                        let isLinked = focusTimerVM.linkedTaskIDs.contains(task.id)
                        Button {
                            if isLinked {
                                focusTimerVM.unlink(taskID: task.id)
                            } else {
                                focusTimerVM.link(taskID: task.id)
                            }
                        } label: {
                            Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    isLinked ? themeManager.palette.accent : themeManager.palette.border
                                )
                        }
                        .buttonStyle(.plain)

                        Text(task.title)
                            .font(.system(size: 13))
                            .foregroundStyle(themeManager.palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(themeManager.palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: - Today Stats
    private var todayStatsSection: some View {
        HStack(spacing: 12) {
            focusStat(
                label: "Focus today",
                value: formatDuration(focusTimerVM.totalFocusTimeToday),
                icon: "brain.head.profile"
            )
            focusStat(
                label: "Sessions",
                value: "\(focusTimerVM.completedPomodoros)",
                icon: "timer"
            )
        }
    }

    private func focusStat(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(themeManager.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(themeManager.palette.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Settings
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.palette.textTertiary)
                .textCase(.uppercase)

            VStack(spacing: 12) {
                settingRow(
                    label: "Work duration",
                    value: formatMinutes(focusTimerVM.config.workDurationSeconds / 60),
                    icon: "brain"
                ) {
                    Stepper(
                        "",
                        value: Binding(
                            get: { focusTimerVM.config.workDurationSeconds / 60 },
                            set: { focusTimerVM.config.workDurationSeconds = $0 * 60 }
                        ),
                        in: 5...90,
                        step: 5
                    )
                }

                settingRow(
                    label: "Short break",
                    value: formatMinutes(focusTimerVM.config.shortBreakSeconds / 60),
                    icon: "cup.and.saucer"
                ) {
                    Stepper(
                        "",
                        value: Binding(
                            get: { focusTimerVM.config.shortBreakSeconds / 60 },
                            set: { focusTimerVM.config.shortBreakSeconds = $0 * 60 }
                        ),
                        in: 1...30,
                        step: 1
                    )
                }

                settingRow(
                    label: "Long break",
                    value: formatMinutes(focusTimerVM.config.longBreakSeconds / 60),
                    icon: "moon.zzz"
                ) {
                    Stepper(
                        "",
                        value: Binding(
                            get: { focusTimerVM.config.longBreakSeconds / 60 },
                            set: { focusTimerVM.config.longBreakSeconds = $0 * 60 }
                        ),
                        in: 5...60,
                        step: 5
                    )
                }

                Toggle("Enable Do Not Disturb", isOn: $focusTimerVM.config.enableDND)
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.palette.textPrimary)
                    .toggleStyle(.switch)

                Toggle("Auto-start breaks", isOn: $focusTimerVM.config.autoStartBreaks)
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.palette.textPrimary)
                    .toggleStyle(.switch)
            }
            .padding(14)
            .background(themeManager.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func settingRow<Control: View>(
        label: String,
        value: String,
        icon: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(themeManager.palette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(themeManager.palette.textSecondary)
            control()
        }
    }

    // MARK: - Helpers
    private var primaryButtonIcon: String {
        switch focusTimerVM.state {
        case .idle:      return "play.fill"
        case .running, .break_:   return "pause.fill"
        case .paused:    return "play.fill"
        case .completed: return "arrow.counterclockwise"
        }
    }

    private var stateLabel: String {
        switch focusTimerVM.state {
        case .idle:      return "Ready to focus"
        case .running:   return "In the zone"
        case .paused:    return "Paused"
        case .break_:    return "Take a break"
        case .completed: return "Session complete!"
        }
    }

    private var phaseGradient: LinearGradient {
        switch focusTimerVM.currentPhase {
        case .work:
            return LinearGradient(
                colors: [themeManager.palette.accent, themeManager.palette.accentSecondary],
                startPoint: .top, endPoint: .bottom
            )
        case .shortBreak:
            return LinearGradient(
                colors: [themeManager.palette.success, themeManager.palette.accentSecondary],
                startPoint: .top, endPoint: .bottom
            )
        case .longBreak:
            return LinearGradient(
                colors: [.orange, themeManager.palette.warning],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        "\(minutes) min"
    }
}
