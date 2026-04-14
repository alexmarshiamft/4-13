// HabitView.swift – Habit tracking dashboard with streak visualization
// Lumina: AI-powered reminders, task management, and focus app
//
// Module F: Habit & Recurrence Engine UI

import SwiftUI
import SwiftData

// MARK: - HabitView
struct HabitView: View {

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - SwiftData
    @Query(filter: #Predicate<LuminaHabit> { !$0.isArchived },
           sort: \LuminaHabit.createdAt, order: .reverse)
    private var habits: [LuminaHabit]

    // MARK: - State
    @State private var showAddHabit = false
    @State private var selectedHabit: LuminaHabit? = nil
    @State private var selectedCategory: HabitCategory? = nil

    private var filteredHabits: [LuminaHabit] {
        guard let cat = selectedCategory else { return habits }
        return habits.filter { $0.category == cat }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            habitHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // ── Stats Row ─────────────────────────────────────────────────────
            statsRow
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // ── Category Filter ───────────────────────────────────────────────
            categoryFilter
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider().background(themeManager.palette.border)

            // ── Habit Grid ────────────────────────────────────────────────────
            if filteredHabits.isEmpty {
                emptyState
            } else {
                habitGrid
            }
        }
        .background(themeManager.palette.backgroundPrimary)
        .sheet(isPresented: $showAddHabit) { AddHabitView() }
        .sheet(item: $selectedHabit) { habit in HabitDetailView(habit: habit) }
    }

    // MARK: - Header
    private var habitHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Habits")
                    .font(.title2.bold())
                    .foregroundStyle(themeManager.palette.textPrimary)
                Text("\(habits.filter { $0.isCompletedToday }.count)/\(habits.count) done today")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.textSecondary)
            }
            Spacer()
            Button {
                showAddHabit = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(
                value: "\(totalStreakDays)",
                label: "Total Streak Days",
                icon: "flame.fill",
                color: .orange
            )
            statCard(
                value: "\(habits.filter { $0.isCompletedToday }.count)",
                label: "Completed Today",
                icon: "checkmark.circle.fill",
                color: themeManager.palette.success
            )
            statCard(
                value: String(format: "%.0f%%", avgCompletionRate * 100),
                label: "30-Day Rate",
                icon: "chart.line.uptrend.xyaxis",
                color: themeManager.palette.accent
            )
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.palette.textPrimary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(themeManager.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Category Filter
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(HabitCategory.allCases, id: \.self) { cat in
                    categoryChip(cat, label: cat.rawValue.capitalized)
                }
            }
        }
    }

    private func categoryChip(_ cat: HabitCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedCategory = isSelected ? nil : cat
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : themeManager.palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? themeManager.palette.accent : themeManager.palette.backgroundSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Habit Grid
    private var habitGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                spacing: 12
            ) {
                ForEach(filteredHabits) { habit in
                    HabitCardView(habit: habit)
                        .onTapGesture { selectedHabit = habit }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.palette.textTertiary)
            Text("No habits yet")
                .font(.title3.bold())
                .foregroundStyle(themeManager.palette.textPrimary)
            Text("Build lasting routines with streak tracking and smart reminders.")
                .font(.body)
                .foregroundStyle(themeManager.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Add First Habit") { showAddHabit = true }
                .buttonStyle(LuminaPrimaryButtonStyle(palette: themeManager.palette))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Stats
    private var totalStreakDays: Int {
        habits.map(\.currentStreak).max() ?? 0
    }

    private var avgCompletionRate: Double {
        guard !habits.isEmpty else { return 0 }
        let sum = habits.map(\.completionRate30Days).reduce(0, +)
        return sum / Double(habits.count)
    }
}

// MARK: - HabitCardView
struct HabitCardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var habit: LuminaHabit

    var todayEntry: HabitEntry? { habit.entry(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Top row: emoji, name, streak ──────────────────────────────────
            HStack {
                Text(habit.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.palette.textPrimary)
                        .lineLimit(1)
                    Text(habit.category.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(themeManager.palette.textTertiary)
                }
                Spacer()
                // Streak badge
                HStack(spacing: 2) {
                    Text("🔥")
                        .font(.caption)
                    Text("\(habit.currentStreak)")
                        .font(.caption.bold())
                        .foregroundStyle(themeManager.palette.textPrimary)
                }
            }

            // ── Progress bar ──────────────────────────────────────────────────
            let progress = completionProgress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeManager.palette.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.spring(response: 0.4), value: progress)
                }
            }
            .frame(height: 6)

            // ── Completion controls ───────────────────────────────────────────
            HStack {
                Text(progressLabel)
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textSecondary)
                Spacer()
                if habit.dailyGoalCount > 1 {
                    // Multiple completion steppers
                    HStack(spacing: 4) {
                        Button {
                            decrementCompletion()
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(themeManager.palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled((todayEntry?.completionCount ?? 0) == 0)

                        Text("\(todayEntry?.completionCount ?? 0)/\(habit.dailyGoalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(themeManager.palette.textPrimary)

                        Button {
                            incrementCompletion()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(themeManager.palette.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled((todayEntry?.completionCount ?? 0) >= habit.dailyGoalCount)
                    }
                } else {
                    // Simple done / undo toggle
                    Button {
                        toggleCompletion()
                    } label: {
                        Label(
                            habit.isCompletedToday ? "Done" : "Mark Done",
                            systemImage: habit.isCompletedToday ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            habit.isCompletedToday
                                ? themeManager.palette.success
                                : themeManager.palette.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    habit.isCompletedToday
                        ? themeManager.palette.success.opacity(0.5)
                        : themeManager.palette.border,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Computed
    private var completionProgress: Double {
        todayEntry?.completionFraction ?? 0
    }

    private var progressColor: Color {
        if completionProgress >= 1 { return themeManager.palette.success }
        if completionProgress >= 0.5 { return themeManager.palette.warning }
        return themeManager.palette.accent
    }

    private var progressLabel: String {
        if let entry = todayEntry {
            if entry.isCompleted { return "Completed today ✓" }
            if habit.unit != nil {
                return "\(entry.completionCount)/\(habit.dailyGoalCount) \(habit.unit ?? "")"
            }
        }
        return habit.frequency == .daily ? "Daily habit" : habit.frequency.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Actions
    private func toggleCompletion() {
        withAnimation(.spring(response: 0.3)) {
            let entry = getOrCreateTodayEntry()
            if entry.isCompleted {
                entry.reset()
            } else {
                entry.increment()
                habit.lastCompletedDate = Date()
                habit.totalCompletions += 1
                habit.recalculateStreak()
            }
            try? modelContext.save()
        }
    }

    private func incrementCompletion() {
        withAnimation(.spring(response: 0.3)) {
            let entry = getOrCreateTodayEntry()
            entry.increment()
            if entry.isCompleted {
                habit.lastCompletedDate = Date()
                habit.totalCompletions += 1
                habit.recalculateStreak()
            }
            try? modelContext.save()
        }
    }

    private func decrementCompletion() {
        withAnimation {
            let entry = getOrCreateTodayEntry()
            entry.decrement()
            try? modelContext.save()
        }
    }

    private func getOrCreateTodayEntry() -> HabitEntry {
        if let existing = habit.entry(for: Date()) { return existing }
        let entry = HabitEntry(goalCount: habit.dailyGoalCount)
        entry.habit = habit
        habit.entries.append(entry)
        modelContext.insert(entry)
        return entry
    }
}

// MARK: - AddHabitView (sheet)
struct AddHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var name = ""
    @State private var emoji = "⭐"
    @State private var category: HabitCategory = .other
    @State private var frequency: HabitFrequency = .daily
    @State private var goalCount = 1
    @State private var unit = ""
    @State private var hasReminder = false
    @State private var reminderTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji)
                            .frame(width: 60)
                        TextField("Name", text: $name)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue.capitalized, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }
                Section("Goal") {
                    Stepper("Daily goal: \(goalCount)", value: $goalCount, in: 1...100)
                    TextField("Unit (optional, e.g. glasses)", text: $unit)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(HabitFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(freq)
                        }
                    }
                }
                Section("Reminder") {
                    Toggle("Daily Reminder", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("New Habit")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let habit = LuminaHabit(
                            name: name,
                            category: category,
                            emoji: emoji.isEmpty ? "⭐" : emoji,
                            frequency: frequency,
                            reminderTime: hasReminder ? reminderTime : nil,
                            dailyGoalCount: goalCount,
                            unit: unit.isEmpty ? nil : unit
                        )
                        modelContext.insert(habit)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(themeManager.palette.backgroundPrimary)
    }
}

// MARK: - HabitDetailView (sheet)
struct HabitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var habit: LuminaHabit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Streak stats
                    HStack(spacing: 16) {
                        streakStat("Current Streak", value: "\(habit.currentStreak) days", icon: "flame.fill", color: .orange)
                        streakStat("Longest Streak", value: "\(habit.longestStreak) days", icon: "trophy.fill", color: themeManager.palette.warning)
                        streakStat("Total", value: "\(habit.totalCompletions)", icon: "checkmark.circle.fill", color: themeManager.palette.success)
                        streakStat("30-Day Rate", value: String(format: "%.0f%%", habit.completionRate30Days * 100), icon: "chart.line.uptrend.xyaxis", color: themeManager.palette.accent)
                    }

                    // 30-day heatmap
                    habitHeatmap

                    // Edit fields
                    Form {
                        TextField("Name", text: $habit.name)
                        Toggle("Paused", isOn: $habit.isPaused)
                        Toggle("Archived", isOn: $habit.isArchived)
                    }
                    .formStyle(.grouped)
                }
                .padding(20)
            }
            .navigationTitle(habit.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .background(themeManager.palette.backgroundPrimary)
    }

    // MARK: - 30-Day Heatmap
    private var habitHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 30 Days")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.palette.textTertiary)
                .textCase(.uppercase)

            let days = (0..<30).map { offset -> (Date, HabitEntry?) in
                let date = Calendar.current.date(byAdding: .day, value: -(29 - offset), to: Date())!
                return (date, habit.entry(for: date))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 15), spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.0) { _, pair in
                    let (_, entry) = pair
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatmapColor(entry))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(14)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func heatmapColor(_ entry: HabitEntry?) -> Color {
        guard let entry else { return themeManager.palette.border }
        if entry.isCompleted { return themeManager.palette.success }
        if entry.completionCount > 0 { return themeManager.palette.success.opacity(0.4) }
        return themeManager.palette.border
    }

    private func streakStat(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.palette.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(themeManager.palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
