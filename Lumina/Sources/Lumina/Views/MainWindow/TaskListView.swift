// TaskListView.swift – Task list with filtering, sorting, and inline editing
// Lumina: AI-powered reminders, task management, and focus app

import SwiftUI
import SwiftData

// MARK: - Task Filter
enum TaskFilter {
    case today
    case all
    case upcoming
    case completed
    case overdue
    case tag(String)

    var title: String {
        switch self {
        case .today:        return "Today"
        case .all:          return "All Tasks"
        case .upcoming:     return "Upcoming"
        case .completed:    return "Completed"
        case .overdue:      return "Overdue"
        case .tag(let t):   return "#\(t)"
        }
    }

    var systemImage: String {
        switch self {
        case .today:        return "sun.max.fill"
        case .all:          return "checkmark.circle"
        case .upcoming:     return "arrow.right.circle"
        case .completed:    return "checkmark.circle.fill"
        case .overdue:      return "exclamationmark.circle"
        case .tag:          return "tag"
        }
    }
}

// MARK: - TaskListView
struct TaskListView: View {

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notificationScheduler: NotificationScheduler
    @EnvironmentObject private var focusTimerVM: FocusTimerViewModel

    // MARK: - SwiftData
    @Query(sort: \LuminaTask.createdAt, order: .reverse) private var allTasks: [LuminaTask]

    // MARK: - Props
    let filter: TaskFilter

    // MARK: - State
    @State private var searchText: String = ""
    @State private var showCompleted: Bool = false
    @State private var selectedSort: TaskSortOption = .dueDate
    @State private var selectedTask: LuminaTask? = nil
    @State private var showAddTask: Bool = false
    @State private var conflictSheetTask: LuminaTask? = nil

    // MARK: - Filtered & Sorted Tasks
    private var filteredTasks: [LuminaTask] {
        var tasks = allTasks

        // Apply filter
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        switch filter {
        case .today:
            tasks = tasks.filter { task in
                guard let due = task.effectiveDueDate else { return false }
                return due >= today && due < tomorrow
            }
        case .all:
            if !showCompleted {
                tasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
            }
        case .upcoming:
            tasks = tasks.filter { task in
                guard let due = task.effectiveDueDate else { return false }
                return due > Date() && task.status != .completed
            }
        case .completed:
            tasks = tasks.filter { $0.status == .completed }
        case .overdue:
            tasks = tasks.filter { $0.isOverdue }
        case .tag(let tag):
            tasks = tasks.filter { $0.tags.contains(tag) }
        }

        // Apply search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            tasks = tasks.filter {
                $0.title.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q) ||
                $0.tags.contains(where: { $0.contains(q) })
            }
        }

        // Sort
        switch selectedSort {
        case .dueDate:
            tasks.sort {
                let a = $0.effectiveDueDate ?? Date.distantFuture
                let b = $1.effectiveDueDate ?? Date.distantFuture
                return a < b
            }
        case .priority:
            tasks.sort { $0.priorityRaw > $1.priorityRaw }
        case .created:
            tasks.sort { $0.createdAt > $1.createdAt }
        case .alphabetical:
            tasks.sort { $0.title < $1.title }
        }

        return tasks
    }

    // Grouped by priority for "All Tasks" view
    private var groupedTasks: [(String, [LuminaTask])] {
        let overdue  = filteredTasks.filter { $0.isOverdue }
        let today    = filteredTasks.filter { task in
            guard let d = task.effectiveDueDate else { return false }
            return !task.isOverdue && Calendar.current.isDateInToday(d)
        }
        let upcoming = filteredTasks.filter { task in
            guard let d = task.effectiveDueDate else { return false }
            return !task.isOverdue && !Calendar.current.isDateInToday(d) && d > Date()
        }
        let noDate   = filteredTasks.filter { $0.effectiveDueDate == nil }

        var groups: [(String, [LuminaTask])] = []
        if !overdue.isEmpty  { groups.append(("⚠ Overdue", overdue)) }
        if !today.isEmpty    { groups.append(("Today", today)) }
        if !upcoming.isEmpty { groups.append(("Upcoming", upcoming)) }
        if !noDate.isEmpty   { groups.append(("No Date", noDate)) }
        return groups
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // ── Top Bar ───────────────────────────────────────────────────────
            listHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // ── Search ────────────────────────────────────────────────────────
            searchBar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider()
                .background(themeManager.palette.border)

            // ── Task List ─────────────────────────────────────────────────────
            if filteredTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(themeManager.palette.backgroundPrimary)
        .sheet(isPresented: $showAddTask) {
            QuickCaptureView()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
    }

    // MARK: - List Header
    private var listHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.title)
                    .font(.title2.bold())
                    .foregroundStyle(themeManager.palette.textPrimary)
                Text("\(filteredTasks.count) task\(filteredTasks.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                // Sort picker
                Menu {
                    ForEach(TaskSortOption.allCases, id: \.self) { opt in
                        Button(opt.label) { selectedSort = opt }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14))
                        .foregroundStyle(themeManager.palette.textSecondary)
                }
                .buttonStyle(.plain)

                // Show/hide completed toggle
                Toggle(isOn: $showCompleted) {
                    Image(systemName: showCompleted ? "eye.fill" : "eye.slash")
                        .font(.system(size: 14))
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(themeManager.palette.textSecondary)
                .help(showCompleted ? "Hide completed" : "Show completed")

                // Add task button
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(themeManager.palette.accent)
                }
                .buttonStyle(.plain)
                .help("Add task (⌘⇧N)")
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(themeManager.palette.textTertiary)
            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(themeManager.palette.textPrimary)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeManager.palette.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Task List
    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedTasks, id: \.0) { group in
                    Section {
                        ForEach(group.1) { task in
                            TaskRowView(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTask = task }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                        }
                    } header: {
                        sectionHeader(group.0)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(themeManager.palette.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(themeManager.palette.backgroundPrimary)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: filter.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(themeManager.palette.textTertiary)
            Text(emptyStateTitle)
                .font(.title3.bold())
                .foregroundStyle(themeManager.palette.textPrimary)
            Text(emptyStateMessage)
                .font(.body)
                .foregroundStyle(themeManager.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Add a Task") { showAddTask = true }
                .buttonStyle(LuminaPrimaryButtonStyle(palette: themeManager.palette))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch filter {
        case .today:     return "Nothing due today"
        case .all:       return "No tasks yet"
        case .overdue:   return "All caught up!"
        case .completed: return "No completed tasks"
        default:         return "Nothing here"
        }
    }

    private var emptyStateMessage: String {
        switch filter {
        case .today:     return "Add a task with ⌘⇧N or just start typing."
        case .all:       return "Your task list is empty. Add your first task."
        case .overdue:   return "You're on top of everything. Keep it up!"
        default:         return "Add a task to get started."
        }
    }
}

// MARK: - Sort Options
enum TaskSortOption: CaseIterable {
    case dueDate, priority, created, alphabetical
    var label: String {
        switch self {
        case .dueDate:      return "Due Date"
        case .priority:     return "Priority"
        case .created:      return "Created"
        case .alphabetical: return "A–Z"
        }
    }
}

// MARK: - TaskRowView
struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var task: LuminaTask

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    if task.isCompleted {
                        task.status = .pending
                    } else {
                        task.markCompleted()
                    }
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        task.isCompleted
                            ? themeManager.palette.success
                            : themeManager.palette.border
                    )
            }
            .buttonStyle(.plain)

            // Task info
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        task.isCompleted
                            ? themeManager.palette.textTertiary
                            : themeManager.palette.textPrimary
                    )
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let due = task.effectiveDueDate {
                        Label(due.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(
                                task.isOverdue
                                    ? themeManager.palette.destructive
                                    : themeManager.palette.textTertiary
                            )
                    }
                    ForEach(task.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(themeManager.palette.accent)
                    }
                }
            }

            Spacer()

            // Priority indicator
            if task.priority != .none {
                Image(systemName: task.priority.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(priorityColor(task.priority))
            }

            // Recurrence indicator
            if task.isRecurring {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(task.isCompleted ? 0.55 : 1)
        .contextMenu {
            taskContextMenu
        }
    }

    private var taskContextMenu: some View {
        Group {
            Button("Mark Complete") { task.markCompleted() }
            Button("Snooze 15 min") { task.snooze(by: 900) }
            Divider()
            Button("Delete", role: .destructive) { modelContext.delete(task) }
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none:   return themeManager.palette.textTertiary
        case .low:    return themeManager.palette.success
        case .medium: return themeManager.palette.warning
        case .high:   return .orange
        case .urgent: return themeManager.palette.destructive
        }
    }
}

// MARK: - TaskDetailView (sheet)
struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var task: LuminaTask

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $task.title)
                    TextEditor(text: $task.notes)
                        .frame(minHeight: 80)
                }
                Section("Scheduling") {
                    DatePicker("Due Date", selection: Binding(
                        get: { task.dueDate ?? Date() },
                        set: { task.dueDate = $0 }
                    ), displayedComponents: [.date])
                    DatePicker("Due Time", selection: Binding(
                        get: { task.dueTime ?? Date() },
                        set: { task.dueTime = $0 }
                    ), displayedComponents: [.hourAndMinute])
                }
                Section("Priority") {
                    Picker("Priority", selection: Binding(
                        get: { task.priority },
                        set: { task.priority = $0 }
                    )) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Label(p.label, systemImage: p.systemImage).tag(p)
                        }
                    }
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(themeManager.palette.backgroundPrimary)
    }
}
