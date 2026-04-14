# Lumina — Folder Structure

```
Lumina/
│
├── Package.swift                          # Swift Package Manager manifest (macOS 14+, iOS 17+, watchOS 10+)
│
├── Sources/
│   └── Lumina/
│       │
│       ├── App/
│       │   └── LuminaApp.swift            # @main entry point, WindowGroup, MenuBarExtra, commands
│       │
│       ├── Models/                        # SwiftData persistent models
│       │   ├── LuminaTask.swift           # Task model with NLP fields, scheduling, recurrence, triggers
│       │   ├── LuminaHabit.swift          # Habit model with frequency, streak tracking, recurrence rule
│       │   ├── HabitEntry.swift           # Per-day completion record (count, mood, notes)
│       │   └── FocusSession.swift         # Pomodoro session with phase, status, linked tasks
│       │
│       ├── Modules/
│       │   ├── NLP/
│       │   │   └── NLPParser.swift        # Module A: on-device NL parsing (NaturalLanguage framework)
│       │   │                              #   → extracts: title, date, time, priority, tags, recurrence
│       │   ├── Notifications/
│       │   │   └── NotificationScheduler.swift  # Module B: smart snooze, EventKit busy-check
│       │   ├── Calendar/
│       │   │   └── CalendarSyncManager.swift    # Module D: two-way EventKit sync, conflict detection
│       │   ├── Location/
│       │   │   └── LocationManager.swift        # Module E: CoreLocation geofencing, Wi-Fi SSID triggers
│       │   └── StoreKit/
│       │       └── StoreManager.swift           # StoreKit 2 hybrid model ($14.99 + Pro Pass)
│       │
│       ├── Views/
│       │   ├── QuickCapture/
│       │   │   ├── QuickCaptureView.swift        # Global capture panel (⌘⇧N, NLP preview, voice)
│       │   │   └── QuickCaptureViewModel.swift   # VM: parse, save, SFSpeechRecognizer
│       │   ├── MainWindow/
│       │   │   ├── ContentView.swift             # NavigationSplitView shell, sidebar, toolbar
│       │   │   ├── TaskListView.swift            # Task list with groups, sort, search, inline edit
│       │   │   └── HabitView.swift               # Habit grid, streak chart, 30-day heatmap
│       │   ├── MenuBar/
│       │   │   └── MenuBarView.swift             # Compact menu bar dropdown (today tasks + focus timer)
│       │   ├── Focus/
│       │   │   ├── FocusTimerView.swift          # Pomodoro ring UI, controls, session settings
│       │   │   └── FocusTimerViewModel.swift     # Timer state machine (work/break/long-break)
│       │   └── Shared/
│       │       └── ThemeManager.swift            # Deep Space Dark + Minimalist Light theming
│       │
│       └── Resources/                    # App icons, Assets, Entitlements (add in Xcode)
│
└── Tests/
    └── LuminaTests/
        └── LuminaTests.swift             # Unit tests: NLPParser, models, recurrence, theme
```

## Architecture Overview

### Data Layer — SwiftData + CloudKit
All four models (`LuminaTask`, `LuminaHabit`, `HabitEntry`, `FocusSession`) use the `@Model` macro.
The `ModelContainer` is initialised with `cloudKitDatabase: .private("iCloud.com.lumina.app")` for
end-to-end encrypted, zero-server private iCloud sync.

### Module Breakdown

| Module | File | Key Dependency |
|--------|------|----------------|
| A – NLP Capture | `NLPParser.swift` | `NaturalLanguage`, `Speech` |
| B – Smart Notifications | `NotificationScheduler.swift` | `UserNotifications`, `EventKit` |
| C – Focus Timer | `FocusTimerViewModel.swift` | `UserNotifications`, AppKit DND |
| D – Calendar Sync | `CalendarSyncManager.swift` | `EventKit` |
| E – Location Triggers | `LocationManager.swift` | `CoreLocation`, `NetworkExtension` |
| F – Habit Engine | `LuminaHabit.swift` + `HabitView.swift` | SwiftData |
| – StoreKit | `StoreManager.swift` | `StoreKit` |
| – Themes | `ThemeManager.swift` | SwiftUI |

### Three UI Modes

1. **Main Window** — `ContentView.swift` (NavigationSplitView, full feature set)
2. **Quick Capture** — `QuickCaptureView.swift` (floating panel, ⌘⇧N shortcut)
3. **Menu Bar** — `MenuBarView.swift` (MenuBarExtra dropdown, ~320 px wide)

### Monetisation — StoreKit 2

```
$14.99 base (com.lumina.app.base)
  └── Core features: forever
  └── New features: 1 year from purchase date

Lumina Pro Pass (com.lumina.pro.annual / .monthly)
  └── Continued access to features released after the 1-year window
```

Receipt validation in `StoreManager.refreshPurchaseState()` reads `Transaction.currentEntitlements`
and compares `purchaseDate` against the 1-year boundary to determine feature gating via `isUnlocked(_:)`.
