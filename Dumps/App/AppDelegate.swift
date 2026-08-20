import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    var captureController: CaptureController?
    var hotkeyManager: HotkeyManager?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDatabase()
        setupActiveBucket()
        setupCapture()
        setupHotkey()
        setupStatusItem()
        registerTerminationHandler()
        showFirstRunHintIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Preserve any in-flight capture draft
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
        }
    }

    // MARK: - Active Bucket

    private func setupActiveBucket() {
        let store = ActiveBucketStore.shared
        store.load()
        if store.activeBucketId == nil, let first = BucketRepository().listActive().first {
            store.setActive(id: first.id)
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

    // MARK: - Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "Dumps")
        }
        item.menu = buildStatusMenu()
        self.statusItem = item
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

    @objc private func openLibrary() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey { window.makeKeyAndOrderFront(nil); return }
    }
    @objc private func newDump() { captureController?.show() }
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { NSSound.beep() }
            statusItem?.menu = buildStatusMenu()
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

    private func registerTerminationHandler() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillTerminate), name: NSApplication.willTerminateNotification, object: nil)
    }
    @objc private func handleWillTerminate() {
        if let c = captureController, c.state != .hidden { c.hide(preserveDraft: true) }
    }

    private func showFirstRunHintIfNeeded() {
        let key = "hasShownFirstRunHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "Welcome to Dumps"
        alert.informativeText = "Press Option + Space to capture a dump from anywhere.\n\nShortcuts:\n  ⌘N — New dump\n  ⌘F — Search\n  ⌘, — Settings"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }
}
