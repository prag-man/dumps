# Dumps

<p align="center">
  <strong>Dump the thought. Keep the flow.</strong><br>
  An ultralight, local-first thought capture utility for macOS.
</p>

<p align="center">
  <code>⌥ Space</code> → type → <code>Enter</code>. Done.
</p>

---

Dumps gives you one tiny place to get a thought out of your head without switching context.

Press the shortcut from anywhere on your Mac. A minimal capture surface appears beneath the notch. Type whatever is in your head, choose a bucket if you need to, press Enter, and get back to what you were doing.

No account. No cloud. No workspace to maintain.

<p align="center">
  <a href="https://github.com/prag-man/dumps/releases/latest">
    <img alt="Download" src="https://img.shields.io/github/v/release/prag-man/dumps?label=Download&color=5E6AD2">
  </a>
  <img alt="CI" src="https://github.com/prag-man/dumps/actions/workflows/ci.yml/badge.svg">
  <img alt="Release" src="https://github.com/prag-man/dumps/actions/workflows/release.yml/badge.svg">
</p>

> Screenshots and capture demo GIF will be added next — the app icon is now in the build.

## Capture from anywhere

- **`⌥ Space`** — open / hide Capture
- **`Enter`** — save
- **`Shift + Enter`** — new line
- **`Shift + Tab`** — next bucket
- **`Esc`** — discard

If you hide Capture without discarding, your unfinished thought is preserved locally for the next time you open it.

## A feed for how you actually thought

Dumps keeps a day-wise thread of everything you captured.

- newest days first,
- thoughts stay in the order you captured them,
- move a dump between buckets without changing its place in history,
- search across your local library,
- edit or clean things up later.

Capture first. Organize later.

## Buckets, not bureaucracy

Buckets are intentionally simple.

Use them for things like:

- Inbox
- Work
- Ideas
- Personal
- Reading

`Shift + Tab` moves through your bucket order while capturing. Drag buckets in the sidebar to reorder — Shift+Tab follows the same order.

No nested folder trees. No databases. No setup ceremony.

## Local by design

Dumps is built as a local macOS utility.

- no account,
- no backend,
- no cloud sync,
- no analytics pipeline,
- no dump content sent to a server,
- local SQLite database,
- works offline.

Your dumps live on your Mac.

## Built to stay out of the way

Dumps is native Swift + AppKit + SwiftUI with SQLite underneath.

The capture path is deliberately small:

```
shortcut
→ capture
→ local transaction
→ gone
```

No browser shell. No sync engine. No server round trip.

> Performance measurements will be published from Release builds once the benchmark suite is locked.

## Install

### Download

Download the latest build from **GitHub Releases** — signed with Developer ID Application (notarization coming once App Store Connect API key is added):

  https://github.com/prag-man/dumps/releases/latest

1. Open the `.dmg`.
2. Drag **Dumps** into Applications.
3. Launch Dumps.
4. Choose your capture shortcut if `⌥ Space` is already in use.
5. Optionally enable **Launch at Login**.

### Build from source

Requirements:

- macOS 14+
- Xcode 15+

```bash
git clone https://github.com/prag-man/dumps.git
cd dumps
open Dumps.xcodeproj
```

Or:

```bash
xcodebuild \
  -project Dumps.xcodeproj \
  -scheme Dumps \
  -configuration Debug \
  build
```

Run tests:

```bash
xcodebuild test \
  -project Dumps.xcodeproj \
  -scheme Dumps \
  -destination 'platform=macOS'
```

## Where the data lives

By default:

```
~/Library/Application Support/Dumps/dumps.sqlite
```

Dumps uses SQLite in WAL mode.

## Architecture

```
Dumps.app
├── Capture
│   ├── global hotkey
│   ├── notch/top-center panel
│   └── local draft recovery
├── Core
│   ├── dumps
│   ├── buckets
│   └── active capture bucket
├── Database
│   └── SQLite
└── Library
    ├── Feed
    ├── Search
    └── Settings
```

The app intentionally has no backend in v1.

## Contributing

Issues and small focused pull requests are welcome.

Before opening a PR:

```bash
xcodebuild test \
  -project Dumps.xcodeproj \
  -scheme Dumps \
  -destination 'platform=macOS'
```

Please keep Dumps small. New features should not make the capture path slower, heavier, or dependent on a network connection.

## License

MIT — see [`LICENSE`](LICENSE).
