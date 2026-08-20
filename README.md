# Dumps

A fast, keyboard-first macOS scratchpad for capturing thoughts into buckets.

![Dumps screenshot](https://via.placeholder.com/800x500?text=Dumps+Screenshot)

## Features

- **Instant capture** — Press `Option + Space` from anywhere to dump a thought.
- **Buckets** — Organize dumps into named buckets; drag to reorder.
- **Feed** — Chronological feed grouped by day, newest first.
- **Search** — Filter dumps by content, optionally scoped to a bucket.
- **Soft delete & restore** — Deleted dumps can be restored.
- **Draft persistence** — In-progress capture is saved on quit and restored on launch.
- **Menu bar** — Quick access via the `tray` icon: open library, new dump, active bucket, launch at login, settings, quit.
- **Launch at Login** — Toggle via Settings or the menu bar (uses `SMAppService` on macOS 13+).

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5

No external dependencies — pure Swift/SwiftUI + AppKit + SQLite3.

## Build & Run

```bash
open Dumps.xcodeproj
```

Then select the **Dumps** scheme and press `⌘R`, or build from the command line:

```bash
xcodebuild -project Dumps.xcodeproj -scheme Dumps -configuration Debug build
```

Run tests:

```bash
xcodebuild test -project Dumps.xcodeproj -scheme Dumps -destination 'platform=macOS'
```

## Architecture

```
Dumps/
├── App/               # App lifecycle
│   ├── DumpsApp.swift      # @main SwiftUI App, WindowGroup + Settings + MenuBarExtra
│   └── AppDelegate.swift   # NSApplicationDelegate: DB, capture, hotkey, status item
├── Capture/           # Global capture
│   ├── CaptureState.swift
│   ├── CapturePanel.swift  # NSPanel (floating)
│   ├── CaptureView.swift
│   ├── CaptureController.swift
│   ├── HotkeyManager.swift # Carbon EventHotKey (Option+Space)
│   ├── DraftStore.swift    # UserDefaults-backed draft persistence
│   └── ScreenResolver.swift
├── Core/
│   ├── Models/
│   │   ├── Bucket.swift
│   │   ├── Dump.swift
│   │   └── DayGroup.swift  # Feed day-grouping helper
│   ├── Repositories/
│   │   ├── BucketRepository.swift
│   │   └── DumpRepository.swift
│   ├── ActiveBucketStore.swift
│   └── Preferences.swift   # ObservableObject + SMAppService
├── Database/
│   ├── DatabaseManager.swift  # SQLite3 wrapper (file + :memory: for tests)
│   └── Migrations.swift
├── Library/
│   ├── LibraryWindow.swift # NavigationSplitView (Sidebar + Feed)
│   ├── Sidebar/
│   ├── Feed/
│   ├── Search/
│   ├── DumpEditor/
│   └── Settings/
└── Resources/
    └── Assets.xcassets

DumpsTests/
└── DumpsTests.swift    # XCTest suite (in-memory SQLite)
```

### Data Flow

```
HotkeyManager --(toggle)--> CaptureController --(create)--> DumpRepository --> SQLite
                                                        \
ActiveBucketStore <-- BucketRepository <-- DatabaseManager
Preferences --(SMAppService)--> Launch at Login
DraftStore <--> UserDefaults (survives termination)
```

### Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + AppKit (`NSPanel`, `NSStatusItem`, `NSAlert`) |
| Persistence | SQLite3 (via `libsqlite3`, WAL mode) |
| Login item | `ServiceManagement` / `SMAppService` |
| Hotkey | Carbon `RegisterEventHotKey` |
| State | `ObservableObject` / `@Published` / `@StateObject` |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Option + Space` | Toggle capture panel (global) |
| `⌘N` | New dump |
| `⌘F` | Focus search |
| `⌘,` | Open Settings |
| `⌘Q` | Quit |
| `Esc` | Dismiss capture |
| `⌘Return` | Save capture |

## Project Structure

See **Architecture** above. Key conventions:

- Repositories own all SQL; views never touch `DatabaseManager` directly.
- `DatabaseManager` supports `:memory:` databases for hermetic tests.
- `DayGroup.group(_:)` groups pre-sorted dumps by calendar day for the feed.

## License

MIT
