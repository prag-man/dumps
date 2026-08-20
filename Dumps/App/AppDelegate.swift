import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    var captureController: CaptureController?
    var hotkeyManager: HotkeyManager?
    var statusItem: NSStatusItem?
    var libraryWindowController: LibraryWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDatabase()
        setupActiveBucket()
        setupCapture()
        setupHotkey()
        setupStatusItem()
        observePreferences()
        showFirstRunHintIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Preserve any in-flight capture draft (single termination handler — no duplicate observer)
        if let c = captureController, c.state != .hidden {
            c.hide(preserveDraft: true)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Database

    private func setupDatabase() {
        do { try DatabaseManager.shared.open() } catch { debugPrint("[AppDelegate] DB open failed: \(error)") }
        DatabaseManager.shared.withDB { db in
            try? Migrations.runMigrations(db: db)
            // Bootstrap is also called inside runMigrations; this is a safety net for
            // existing installs where migrations already ran but Inbox is missing.
            try? Migrations.bootstrapIfNeeded(db: db)
        }
    }

    // MARK: - Active Bucket

    private func setupActiveBucket() {
        let store = ActiveBucketStore.shared
        // Ensure bootstrap at AppDelegate level (idempotent) before resolving active bucket.
        DatabaseManager.shared.withDB { db in
            try? Migrations.bootstrapIfNeeded(db: db)
        }
        store.load()
        if store.activeBucketId == nil {
            if let first = BucketRepository().listActive().first {
                store.setActive(id: first.id)
            } else {
                // No buckets at all — create Inbox via repository (covers fresh install edge)
                if let inbox = try? BucketRepository().create(name: "Inbox") {
                    store.load()
                    store.setActive(id: inbox.id)
                } else {
                    // Fallback: reload in case bootstrap created Inbox on another path
                    DatabaseManager.shared.withDB { db in try? Migrations.bootstrapIfNeeded(db: db) }
                    store.load()
                    if let first = BucketRepository().listActive().first {
                        store.setActive(id: first.id)
                    } else {
                        store.fallbackIfNeeded()
                    }
                }
            }
        } else {
            store.fallbackIfNeeded()
        }
        // Also seed main-thread store used by DumpsApp
        // (DumpsApp creates its own ActiveBucketStore instance via @StateObject)
    }

    // MARK: - Capture

    private func setupCapture() {
        let controller = CaptureController(bucketStore: ActiveBucketStore.shared)
        if let draft = DraftStore.shared.load(),
           !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            controller.content = draft.content
            if let bid = draft.bucketId, !bid.isEmpty,
               let bucket = ActiveBucketStore.shared.buckets.first(where: { $0.id == bid }) {
                controller.activeBucket = bucket
            }
            controller.captureState.content = draft.content
            controller.captureState.selectedBucketId = draft.bucketId
        }
        self.captureController = controller
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let manager = HotkeyManager()
        manager.register { [weak self] in
            DispatchQueue.main.async { self?.captureController?.toggle() }
        }
        self.hotkeyManager = manager
    }

    // MARK: - Library (lazy)

    @objc func openLibrary() {
        if libraryWindowController == nil {
            libraryWindowController = LibraryWindowController()
        } else {
            libraryWindowController?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Preferences observation

    private func observePreferences() {
        Preferences.shared.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemVisibility() }
            .store(in: &cancellables)
        // Ensure initial visibility matches preference
        updateStatusItemVisibility()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        guard Preferences.shared.showMenuBarIcon else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "Dumps")
        }
        item.menu = buildStatusMenu()
        self.statusItem = item
    }

    func updateStatusItemVisibility() {
        let shouldShow = Preferences.shared.showMenuBarIcon
        if shouldShow {
            if statusItem == nil { setupStatusItem() }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Dumps", action: #selector(openLibrary), keyEquivalent: "")
        openItem.target = self; menu.addItem(openItem)
        let newItem = NSMenuItem(title: "New Dump", action: #selector(newDump), keyEquivalent: "n")
        newItem.target = self; menu.addItem(newItem)
        menu.addItem(.separator())
        let buckets = BucketRepository().listActive()
        let activeId = ActiveBucketStore.shared.activeBucketId
        let activeName = buckets.first(where: { $0.id == activeId })?.name ?? "Inbox"
        let bucketItem = NSMenuItem(title: "Active: \(activeName)", action: nil, keyEquivalent: "")
        bucketItem.isEnabled = false; menu.addItem(bucketItem)
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        let isEnabled: Bool
        if #available(macOS 13.0, *) { isEnabled = SMAppService.mainApp.status == .enabled }
        else { isEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin") }
        launchItem.state = isEnabled ? .on : .off; menu.addItem(launchItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Dumps", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)
        return menu
    }

    @objc private func newDump() { captureController?.show() }
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { NSSound.beep() }
            statusItem?.menu = buildStatusMenu()
            Preferences.shared.syncLaunchAtLoginFromSystem()
        } else {
            let cur = UserDefaults.standard.bool(forKey: "launchAtLogin")
            UserDefaults.standard.set(!cur, forKey: "launchAtLogin")
            statusItem?.menu = buildStatusMenu()
        }
    }
    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.sendAction(Selector(("showPreferences:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showFirstRunHintIfNeeded() {
        let key = "hasShownFirstRunHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}
