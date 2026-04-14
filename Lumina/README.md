# Lumina

> An AI-powered reminders, task management, and focus app for macOS (primary), iOS, and watchOS.

## Requirements

- **Xcode 15.2+**
- **macOS 14 (Sonoma)** or later (primary target)
- **iOS 17+** / **watchOS 10+** (secondary targets)
- Apple Developer account (for CloudKit, push notifications, StoreKit)

## Getting Started

```bash
# Open in Xcode
open Lumina/Package.swift
```

Or open `Lumina.xcodeproj` if generated via Xcode.

## Project Structure

```
Lumina/
├── App/                         # App entry point, scene setup, keyboard shortcuts
├── Models/                      # SwiftData models (iCloud-synced)
│   ├── LuminaTask               # Task with NLP metadata, scheduling, location triggers
│   ├── LuminaHabit              # Habit with recurrence rules and streak tracking
│   ├── HabitEntry               # Per-day habit completion record
│   └── FocusSession             # Pomodoro session record
├── Modules/
│   ├── NLP/                     # Module A – On-device NLP (NaturalLanguage + Speech)
│   ├── Notifications/           # Module B – Smart notification scheduling (EventKit-aware)
│   ├── Calendar/                # Module D – EventKit two-way sync + conflict detection
│   ├── Location/                # Module E – CoreLocation geofencing + Wi-Fi SSID triggers
│   └── StoreKit/                # StoreKit 2 hybrid purchase model
└── Views/
    ├── QuickCapture/            # Global capture panel (⌘⇧N)
    ├── MainWindow/              # Primary app window (NavigationSplitView)
    ├── MenuBar/                 # Menu Bar Extra dropdown
    ├── Focus/                   # Pomodoro timer UI + ViewModel
    └── Shared/                  # ThemeManager (Deep Space Dark / Minimalist Light)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the complete annotated folder structure and design decisions.

## Key Features

### Module A — Intelligent Capture & NLP
- **Global Quick Capture** panel accessible via `⌘⇧N`
- **On-device NLP** using Apple's `NaturalLanguage` framework — zero network calls
- Parses natural language like *"Call dentist next Friday at 2 PM #health urgent"* into:
  - Task title, due date, due time, priority, tags, recurrence rules
- **Voice-to-Task** via `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
- Live parsing preview with confidence indicator

### Module B — Context-Aware Notification Engine
- **Smart Snooze**: checks system idle time and EventKit free/busy status before firing
- Automatically delays notifications if user is in an active meeting
- Finds the next free calendar slot and reschedules there
- Full notification action suite: Mark Complete / Snooze 5min / Snooze 15min / Open

### Module C — Focus & Deep Work Timer
- **Pomodoro state machine**: Work → Short Break → Work → … → Long Break
- Configurable durations, auto-start options
- Menu bar countdown (`⏱ 24:38`) while session active
- macOS **Do Not Disturb** integration via AppleScript bridge
- Session linked to specific tasks

### Module D — Auto-Rescheduling & Calendar Sync
- Two-way sync with Apple Calendar via EventKit
- Background conflict detection: scans pending tasks against calendar events
- Auto-suggests next available "free block" for conflicting tasks
- Bulk-apply reschedule suggestions

### Module E — Location & Environment Triggers
- **Geofenced tasks**: trigger on Arrive/Leave a named location
- **Wi-Fi SSID triggers**: fire tasks when connecting to a specific network
- All processing on-device with `CoreLocation` and `NetworkExtension`

### Module F — Habit & Recurrence Engine
- Complex recurrence rules: *"every 3rd Friday"*, *"every 3 months"*, *"every Mon and Wed"*
- Streak tracking with current streak, longest streak, 30-day completion rate
- 30-day visual heatmap in the Habit Detail view

## Monetisation — StoreKit 2

| Product | ID | Type |
|---------|-----|------|
| Base App | `com.lumina.app.base` | One-time, $14.99 |
| Pro Pass Monthly | `com.lumina.pro.monthly` | Subscription |
| Pro Pass Annual | `com.lumina.pro.annual` | Subscription |

- Base purchase unlocks **core features forever** + new features for **1 year**
- After the 1-year window, new features require an active **Lumina Pro Pass**
- `StoreManager.isUnlocked(_:)` gates UI features by `FeatureTier` (`.base` / `.proOrRecent` / `.proOnly`)
- Fully receipt-validated via `Transaction.currentEntitlements`

## Themes

| Theme | Description |
|-------|-------------|
| Deep Space Dark | Rich OLED dark palette with deep purple accent |
| Minimalist Light | Clean soft-light palette with indigo accent |
| System | Follows macOS/iOS appearance setting |

## Data & Privacy

- **Zero third-party servers** — all data in iCloud Private Database
- **CloudKit private sync** — encrypted at rest and in transit by Apple
- NLP and speech recognition run **entirely on-device**
- Location data never leaves the device

## Running Tests

Tests cover pure-Swift logic (NLP parsing, model business rules, recurrence, themes):

```bash
# In Xcode: Product → Test (⌘U)
# Or via CLI (requires macOS):
swift test
```

## Entitlements Needed (Xcode)

Add these capabilities to the app target in Xcode:

- `iCloud` (CloudKit container: `iCloud.com.lumina.app`)
- `Push Notifications`
- `Background Modes` → Background fetch, Remote notifications
- `Speech Recognition`
- `Location` → Always + When In Use
- `Access Wi-Fi Information` (for SSID detection)
- `StoreKit` (In-App Purchase)
