// MenuBarView.swift – Compact menu bar dropdown for Lumina
// Lumina: AI-powered reminders, task management, and focus app
//
// Menu Bar utility mode: shows today's tasks, quick-add, and focus timer control

import SwiftUI
import SwiftData

// MARK: - MenuBarView
struct MenuBarView: View {

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var focusTimerVM: FocusTimerViewModel

    // MARK: - SwiftData (today's tasks)
    @Query(sort: \LuminaTask.createdAt, order: .forward)
    private var allTasks: [LuminaTask]

    // MARK: - State
    @State private var quickInput: String = ""
    @State private var showQuickCapture = false

    // Computed
    private var todayTasks: [LuminaTask] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return allTasks.filter { task in
            guard let due = task.effectiveDueDate else { return false }
            return due >= today && due < tomorrow && task.status != .completed
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            menuHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // ── Focus Timer Widget ────────────────────────────────────────────
            focusWidget
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // ── Today's Tasks ─────────────────────────────────────────────────
            tasksSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            // ── Quick Add ─────────────────────────────────────────────────────
            quickAddSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // ── Footer ────────────────────────────────────────────────────────
            menuFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(themeManager.palette.backgroundSecondary)
        .preferredColorScheme(themeManager.colorScheme)
    }

    // MARK: - Header
    private var menuHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(themeManager.accentGradient)
                    .frame(width: 24, height: 24)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Lumina")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeManager.palette.textPrimary)

            Spacer()

            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(themeManager.palette.textTertiary)
        }
    }

    // MARK: - Focus Widget
    private var focusWidget: some View {
        HStack(spacing: 12) {
            // Ring
            ZStack {
                Circle()
                    .stroke(themeManager.palette.border, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: focusTimerVM.isActive ? focusTimerVM.progress : 0)
                    .stroke(themeManager.palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: focusTimerVM.progress)
                Image(systemName: "timer")
                    .font(.system(size: 10))
                    .foregroundStyle(themeManager.palette.textTertiary)
            }
            .frame(width: 32, height: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                if focusTimerVM.isActive {
                    Text(focusTimerVM.formattedTime)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(themeManager.palette.textPrimary)
                    Text(focusTimerVM.phaseLabel)
                        .font(.caption2)
                        .foregroundStyle(themeManager.palette.textSecondary)
                } else {
                    Text("Not focusing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(themeManager.palette.textSecondary)
                    Text("\(focusTimerVM.completedPomodoros) sessions today")
                        .font(.caption2)
                        .foregroundStyle(themeManager.palette.textTertiary)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 8) {
                if focusTimerVM.isActive {
                    Button {
                        focusTimerVM.pauseOrResume()
                    } label: {
                        Image(systemName: focusTimerVM.state == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeManager.palette.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        focusTimerVM.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeManager.palette.destructive)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        focusTimerVM.start()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Focus")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(themeManager.palette.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tasks Section
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(themeManager.palette.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(todayTasks.count)")
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.palette.backgroundTertiary)
                    .clipShape(Capsule())
            }

            if todayTasks.isEmpty {
                Text("Nothing due today 🎉")
                    .font(.system(size: 12))
                    .foregroundStyle(themeManager.palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(todayTasks.prefix(5)) { task in
                    menuTaskRow(task)
                }
                if todayTasks.count > 5 {
                    Text("+ \(todayTasks.count - 5) more…")
                        .font(.caption2)
                        .foregroundStyle(themeManager.palette.textTertiary)
                }
            }
        }
    }

    private func menuTaskRow(_ task: LuminaTask) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation {
                    task.markCompleted()
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        task.isCompleted
                            ? themeManager.palette.success
                            : themeManager.palette.border
                    )
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 12))
                .foregroundStyle(
                    task.isCompleted
                        ? themeManager.palette.textTertiary
                        : themeManager.palette.textPrimary
                )
                .lineLimit(1)
                .strikethrough(task.isCompleted)

            Spacer()

            if let due = task.dueTime {
                Text(due.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(
                        task.isOverdue
                            ? themeManager.palette.destructive
                            : themeManager.palette.textTertiary
                    )
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Quick Add
    private var quickAddSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(themeManager.palette.accent)

            TextField("Quick add task…", text: $quickInput)
                .font(.system(size: 12))
                .foregroundStyle(themeManager.palette.textPrimary)
                .textFieldStyle(.plain)
                .onSubmit {
                    submitQuickTask()
                }

            if !quickInput.isEmpty {
                Button {
                    submitQuickTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(themeManager.palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(themeManager.palette.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Footer
    private var menuFooter: some View {
        HStack {
            Button("Open Lumina") { openMainWindow() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(themeManager.palette.textSecondary)

            Spacer()

            Button("Quick Capture") { showQuickCapture = true }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(themeManager.palette.accent)
                .sheet(isPresented: $showQuickCapture) {
                    QuickCaptureView()
                }
        }
    }

    // MARK: - Actions
    private func submitQuickTask() {
        let text = quickInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let result = NLPParser.shared.parse(text)
        let task = LuminaTask(
            title: result.title.isEmpty ? text : result.title,
            rawInput: text,
            dueDate: result.dueDate,
            dueTime: result.dueTime,
            priority: result.priority,
            tags: result.tags
        )
        modelContext.insert(task)
        try? modelContext.save()
        quickInput = ""
    }

    private func openMainWindow() {
#if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
#endif
    }
}
