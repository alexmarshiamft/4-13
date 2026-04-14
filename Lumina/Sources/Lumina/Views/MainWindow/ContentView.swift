// ContentView.swift – Primary navigation shell for the Lumina main window
// Lumina: AI-powered reminders, task management, and focus app

import SwiftUI
import SwiftData

// MARK: - Navigation Destination
enum NavigationDestination: Hashable, CaseIterable {
    case today
    case tasks
    case habits
    case calendar
    case focus
    case settings

    var label: String {
        switch self {
        case .today:    return "Today"
        case .tasks:    return "All Tasks"
        case .habits:   return "Habits"
        case .calendar: return "Calendar"
        case .focus:    return "Focus"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .tasks:    return "checkmark.circle"
        case .habits:   return "arrow.clockwise.heart.fill"
        case .calendar: return "calendar"
        case .focus:    return "timer"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - ContentView
struct ContentView: View {

    // MARK: - Environment
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var focusTimerVM: FocusTimerViewModel
    @EnvironmentObject private var storeManager: StoreManager

    // MARK: - State
    @State private var selectedDestination: NavigationDestination = .today
    @State private var showQuickCapture = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Body
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ── Sidebar ───────────────────────────────────────────────────────
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // ── Detail ────────────────────────────────────────────────────────
            detailContent
                .background(themeManager.palette.backgroundPrimary)
        }
        .background(themeManager.palette.backgroundPrimary)
        .preferredColorScheme(themeManager.colorScheme)
        .frame(minWidth: 800, minHeight: 550)
        .sheet(isPresented: $showQuickCapture) {
            QuickCaptureView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaOpenQuickCapture)) { _ in
            showQuickCapture = true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                quickCaptureButton
            }
            if focusTimerVM.isActive {
                ToolbarItem(placement: .status) {
                    focusTimerStatusPill
                }
            }
        }
    }

    // MARK: - Sidebar
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Logo / branding
            sidebarHeader

            // Navigation items
            List(NavigationDestination.allCases, id: \.self, selection: $selectedDestination) { dest in
                sidebarRow(dest)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(themeManager.palette.backgroundSecondary)

            Spacer()

            // Focus timer compact widget
            if focusTimerVM.isActive {
                focusTimerSidebarWidget
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            // User / Pro status
            proStatusFooter
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .background(themeManager.palette.backgroundSecondary)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeManager.accentGradient)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Lumina")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(themeManager.palette.textPrimary)
                Text(storeManager.accessLevelDescription)
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func sidebarRow(_ dest: NavigationDestination) -> some View {
        Label(dest.label, systemImage: dest.systemImage)
            .foregroundStyle(
                selectedDestination == dest
                    ? themeManager.palette.accent
                    : themeManager.palette.textSecondary
            )
            .font(.system(size: 13, weight: selectedDestination == dest ? .semibold : .regular))
    }

    // MARK: - Detail
    @ViewBuilder
    private var detailContent: some View {
        switch selectedDestination {
        case .today:
            TaskListView(filter: .today)
        case .tasks:
            TaskListView(filter: .all)
        case .habits:
            HabitView()
        case .calendar:
            CalendarView()
        case .focus:
            FocusTimerView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Quick Capture Toolbar Button
    private var quickCaptureButton: some View {
        Button {
            showQuickCapture = true
        } label: {
            Label("Quick Capture", systemImage: "plus.circle.fill")
                .labelStyle(.iconOnly)
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .help("Quick Capture (⌘⇧N)")
    }

    // MARK: - Focus Timer Status Pill (in toolbar)
    private var focusTimerStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(themeManager.palette.success)
                .frame(width: 6, height: 6)
                .symbolEffect(.pulse)
            Text(focusTimerVM.formattedTime)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(themeManager.palette.textPrimary)
            Text(focusTimerVM.phaseLabel)
                .font(.caption2)
                .foregroundStyle(themeManager.palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(themeManager.palette.surface)
        .clipShape(Capsule())
    }

    // MARK: - Focus Timer Sidebar Widget
    private var focusTimerSidebarWidget: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(themeManager.palette.border, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: focusTimerVM.progress)
                    .stroke(
                        themeManager.palette.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            .animation(.linear(duration: 1), value: focusTimerVM.progress)

            VStack(alignment: .leading, spacing: 1) {
                Text(focusTimerVM.formattedTime)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(themeManager.palette.textPrimary)
                Text(focusTimerVM.phaseLabel)
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textSecondary)
            }

            Spacer()

            Button {
                focusTimerVM.pauseOrResume()
            } label: {
                Image(systemName: focusTimerVM.state == .running ? "pause.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Pro Status Footer
    private var proStatusFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: storeManager.isPurchased ? "checkmark.seal.fill" : "lock.fill")
                .font(.caption)
                .foregroundStyle(
                    storeManager.isPurchased
                        ? themeManager.palette.success
                        : themeManager.palette.textTertiary
                )
            Text(storeManager.accessLevelDescription)
                .font(.caption2)
                .foregroundStyle(themeManager.palette.textTertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(themeManager.palette.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Placeholder Views (CalendarView, SettingsView)
// These are scaffolded here; full implementations are in their own files.

struct CalendarView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.palette.accent)
            Text("Calendar Sync")
                .font(.title2.bold())
                .foregroundStyle(themeManager.palette.textPrimary)
            Text("Two-way EventKit sync with conflict detection and auto-rescheduling.")
                .font(.body)
                .foregroundStyle(themeManager.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.backgroundPrimary)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var storeManager: StoreManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Theme picker
                settingsSection(title: "Appearance") {
                    Picker("Theme", selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Label(theme.displayName, systemImage: theme.systemImage)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // License info
                settingsSection(title: "License") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(storeManager.accessLevelDescription)
                            .font(.headline)
                            .foregroundStyle(themeManager.palette.textPrimary)
                        Button("Restore Purchases") {
                            Task { await storeManager.restorePurchases() }
                        }
                        .buttonStyle(LuminaSecondaryButtonStyle(palette: themeManager.palette))
                    }
                }
            }
            .padding(24)
        }
        .background(themeManager.palette.backgroundPrimary)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeManager.palette.textTertiary)
                .textCase(.uppercase)
            content()
                .padding(16)
                .background(themeManager.palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
