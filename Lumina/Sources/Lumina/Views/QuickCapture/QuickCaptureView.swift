// QuickCaptureView.swift – Global Quick Capture panel for fast task entry
// Lumina: AI-powered reminders, task management, and focus app
//
// Module A: Intelligent Capture & NLP
//  - Accessible via ⌘⇧N global keyboard shortcut
//  - Real-time NLP parsing preview (title, date, time, tags, priority)
//  - Voice-to-Task via SFSpeechRecognizer
//  - Minimal, keyboard-first UI

import SwiftUI
import SwiftData

// MARK: - QuickCaptureView
struct QuickCaptureView: View {

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    // MARK: - ViewModel
    @StateObject private var viewModel = QuickCaptureViewModel()

    // MARK: - Focus
    @FocusState private var inputFocused: Bool

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background blur
            backgroundLayer

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Divider()
                    .background(themeManager.palette.border)
                    .padding(.top, 12)

                // ── Main Input ────────────────────────────────────────────────
                mainInputArea
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // ── NLP Preview ───────────────────────────────────────────────
                if viewModel.showParsedPreview, let result = viewModel.parsedResult {
                    parsedPreview(result: result)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Error ─────────────────────────────────────────────────────
                if let error = viewModel.saveError {
                    errorBanner(message: error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer(minLength: 12)

                Divider()
                    .background(themeManager.palette.border)

                // ── Footer / Actions ─────────────────────────────────────────
                footerBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 560, height: viewModel.showParsedPreview ? 320 : 210)
        .background(themeManager.palette.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.showParsedPreview)
        .onAppear { inputFocused = true }
        .onChange(of: viewModel.inputText) { _, newValue in
            viewModel.onInputChanged(newValue)
        }
    }

    // MARK: - Background
    private var backgroundLayer: some View {
        ZStack {
            themeManager.palette.backgroundSecondary
#if os(macOS)
            // Frosted glass effect on macOS
            VisualEffectView()
                .opacity(0.6)
#endif
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            // App icon / logo
            ZStack {
                Circle()
                    .fill(themeManager.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Quick Capture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.palette.textPrimary)

            Spacer()

            // Keyboard shortcut hint
            shortcutBadge("⌘ ↵", label: "Save")
            shortcutBadge("⎋", label: "Close")
        }
    }

    // MARK: - Main Input
    private var mainInputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Voice button
                Button {
                    viewModel.toggleVoiceDictation()
                } label: {
                    Image(systemName: viewModel.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            viewModel.isListening
                                ? themeManager.palette.accent
                                : themeManager.palette.textTertiary
                        )
                        .symbolEffect(.pulse, isActive: viewModel.isListening)
                }
                .buttonStyle(.plain)
                .help("Voice dictation (on-device)")

                // Text input
                ZStack(alignment: .topLeading) {
                    if viewModel.inputText.isEmpty {
                        Text("What's on your mind? Try "Call dentist next Friday at 2 PM #health"")
                            .font(.system(size: 15))
                            .foregroundStyle(themeManager.palette.textTertiary)
                            .allowsHitTesting(false)
                            .padding(.top, 1)
                    }

                    TextEditor(text: $viewModel.inputText)
                        .font(.system(size: 15))
                        .foregroundStyle(themeManager.palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 60, maxHeight: 100)
                        .focused($inputFocused)
                        .onSubmit { saveTask() }
                }
            }
            .padding(14)
            .background(themeManager.palette.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        inputFocused ? themeManager.palette.accent : themeManager.palette.border,
                        lineWidth: inputFocused ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - NLP Parsed Preview
    private func parsedPreview(result: ParsedTaskResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.accent)
                Text("Lumina detected:")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.textSecondary)
                Spacer()
                confidenceIndicator(result.confidence)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Title chip
                    if !result.title.isEmpty {
                        parsedChip(
                            icon: "text.alignleft",
                            label: result.title,
                            color: themeManager.palette.accent
                        )
                    }

                    // Due date chip
                    if let date = result.dueDate {
                        parsedChip(
                            icon: "calendar",
                            label: date.formatted(date: .abbreviated, time: .omitted),
                            color: themeManager.palette.accentSecondary
                        )
                    }

                    // Due time chip
                    if let time = result.dueTime {
                        parsedChip(
                            icon: "clock",
                            label: time.formatted(date: .omitted, time: .shortened),
                            color: themeManager.palette.accentSecondary
                        )
                    }

                    // Priority chip
                    if result.priority != .none {
                        parsedChip(
                            icon: result.priority.systemImage,
                            label: result.priority.label,
                            color: priorityColor(result.priority)
                        )
                    }

                    // Recurrence chip
                    if result.isRecurring, let rule = result.recurrenceRule {
                        parsedChip(
                            icon: "arrow.clockwise",
                            label: rule.displayString,
                            color: themeManager.palette.success
                        )
                    }

                    // Tag chips
                    ForEach(result.tags, id: \.self) { tag in
                        parsedChip(
                            icon: "tag",
                            label: "#\(tag)",
                            color: themeManager.palette.textSecondary
                        )
                    }

                    // Calendar reference
                    if let calTitle = result.associatedCalendarTitle {
                        parsedChip(
                            icon: "calendar.badge.plus",
                            label: calTitle,
                            color: themeManager.palette.warning
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(themeManager.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(themeManager.palette.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 12) {
            // Priority selector
            Menu {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button {
                        // If parsed result exists, show priority in preview
                    } label: {
                        Label(priority.label, systemImage: priority.systemImage)
                    }
                }
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 14))
                    .foregroundStyle(themeManager.palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Set priority")

            // Tag input hint
            Button {} label: {
                Image(systemName: "tag")
                    .font(.system(size: 14))
                    .foregroundStyle(themeManager.palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Add tags (use #tagname in text)")

            Spacer()

            // Character count
            if !viewModel.inputText.isEmpty {
                Text("\(viewModel.inputText.count) chars")
                    .font(.caption2)
                    .foregroundStyle(themeManager.palette.textTertiary)
            }

            // Cancel button
            Button("Cancel") {
                viewModel.reset()
                dismissWindow()
            }
            .buttonStyle(LuminaSecondaryButtonStyle(palette: themeManager.palette))
            .keyboardShortcut(.escape, modifiers: [])

            // Save button
            Button {
                saveTask()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("Add Task")
                }
            }
            .buttonStyle(LuminaPrimaryButtonStyle(palette: themeManager.palette))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
        }
    }

    // MARK: - Error Banner
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(themeManager.palette.destructive)
            Text(message)
                .font(.caption)
                .foregroundStyle(themeManager.palette.destructive)
            Spacer()
            Button {
                viewModel.saveError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeManager.palette.destructive.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Helper Views
    private func parsedChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func shortcutBadge(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(themeManager.palette.textTertiary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(themeManager.palette.textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(themeManager.palette.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func confidenceIndicator(_ confidence: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / 4.0 < confidence
                          ? themeManager.palette.accent
                          : themeManager.palette.border)
                    .frame(width: 4, height: 8)
            }
        }
        .help("NLP confidence: \(Int(confidence * 100))%")
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

    // MARK: - Actions
    private func saveTask() {
        Task {
            await viewModel.saveTask(
                context: modelContext,
                notificationScheduler: notificationScheduler
            )
        }
    }

    private func dismissWindow() {
#if os(macOS)
        NSApp.keyWindow?.orderOut(nil)
#endif
    }
}

// MARK: - Button Styles

struct LuminaPrimaryButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed
                    ? palette.accent.opacity(0.8)
                    : palette.accent
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct LuminaSecondaryButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed
                    ? palette.backgroundTertiary
                    : palette.backgroundSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}

// MARK: - Visual Effect (macOS frosted glass)
#if os(macOS)
import AppKit

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

// MARK: - Preview
#Preview {
    QuickCaptureView()
        .environmentObject(ThemeManager())
        .environmentObject(NotificationScheduler())
        .modelContainer(for: [LuminaTask.self], inMemory: true)
}
