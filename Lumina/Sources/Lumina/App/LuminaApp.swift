// LuminaApp.swift – Main application entry point
// Lumina: AI-powered reminders, task management, and focus app
// Supports: macOS (primary), iOS, watchOS

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

@main
struct LuminaApp: App {

    // MARK: - SwiftData Container
    let modelContainer: ModelContainer = {
        let schema = Schema([
            LuminaTask.self,
            LuminaHabit.self,
            HabitEntry.self,
            FocusSession.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.lumina.app")
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    // MARK: - Shared State
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var focusTimerVM = FocusTimerViewModel()
    @StateObject private var storeManager = StoreManager()
    @StateObject private var notificationScheduler = NotificationScheduler()

    // MARK: - App Body
    var body: some Scene {
        // ── Main Window ──────────────────────────────────────────────────────
        WindowGroup("Lumina", id: "main") {
            ContentView()
                .modelContainer(modelContainer)
                .environmentObject(themeManager)
                .environmentObject(focusTimerVM)
                .environmentObject(storeManager)
                .environmentObject(notificationScheduler)
                .preferredColorScheme(themeManager.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LuminaCommands()
        }

        // ── Quick Capture Floating Window ────────────────────────────────────
        Window("Quick Capture", id: "quick-capture") {
            QuickCaptureView()
                .modelContainer(modelContainer)
                .environmentObject(themeManager)
                .environmentObject(notificationScheduler)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

#if os(macOS)
        // ── Menu Bar Extra ────────────────────────────────────────────────────
        MenuBarExtra("Lumina", systemImage: "sparkles") {
            MenuBarView()
                .modelContainer(modelContainer)
                .environmentObject(themeManager)
                .environmentObject(focusTimerVM)
        }
        .menuBarExtraStyle(.window)
#endif
    }
}

// MARK: - Keyboard Command Set
struct LuminaCommands: Commands {
    var body: some Commands {
        CommandMenu("Lumina") {
            Button("Quick Capture") {
                openQuickCapture()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Start Focus Session") {
                NotificationCenter.default.post(name: .luminaStartFocus, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }

    private func openQuickCapture() {
#if os(macOS)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "quick-capture" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .luminaOpenQuickCapture, object: nil)
        }
#endif
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let luminaOpenQuickCapture = Notification.Name("luminaOpenQuickCapture")
    static let luminaStartFocus       = Notification.Name("luminaStartFocus")
    static let luminaTaskCreated      = Notification.Name("luminaTaskCreated")
}
