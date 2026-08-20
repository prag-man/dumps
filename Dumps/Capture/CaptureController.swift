import AppKit
import SwiftUI
import Combine
import SQLite3

// Use the test-friendly DatabaseManager primitive where available.

private let SQLITE_TRANSIENT_C = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Observable controller that owns the capture panel lifecycle, draft persistence,
/// hotkey handling, and dump creation.
final class CaptureController: NSObject, ObservableObject, NSWindowDelegate {

    // MARK: - Published State (spec)

    @Published var content: String = ""
    @Published var activeBucket: Bucket?
    @Published var state: CaptureState = .hidden
    @Published var saveError: String?

    // MARK: - AppDelegate compat

    /// Mirrors the older CaptureState object used by AppDelegate.
    /// AppDelegate does: `controller.captureState.content = draft.content`
    var captureState: CaptureStateCompat { _compatState }
    private let _compatState = CaptureStateCompat()

    // MARK: - Dependencies

    private let bucketStore: ActiveBucketStore
    private let draftStore: DraftStore

    // MARK: - Draft cache (DMP-P1-030)

    private var cachedDraft: Draft?

    // MARK: - Panel

    private var panel: CapturePanel?
    private var hostingView: NSHostingView<CaptureView>?
    private var previousApp: NSRunningApplication?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var bucketStoreCancellable: AnyCancellable?

    // MARK: - Focus

    private weak var textViewRef: NSTextView?

    // MARK: - Init

    init(bucketStore: ActiveBucketStore? = nil,
         draftStore: DraftStore = DraftStore.shared,
         hotkeyManager: HotkeyManager? = nil) {
        if let bs = bucketStore {
            self.bucketStore = bs
        } else {
            self.bucketStore = ActiveBucketStore()
        }
        self.draftStore = draftStore
        _ = hotkeyManager
        super.init()
        self.cachedDraft = draftStore.load()
        bind()
        observePanelCancel()
    }

    /// Designated init for tests that want to inject a store.
    init(activeBucketStore: ActiveBucketStore, draftStore: DraftStore = DraftStore.shared) {
        self.bucketStore = activeBucketStore
        self.draftStore = draftStore
        super.init()
        self.cachedDraft = draftStore.load()
        bind()
        observePanelCancel()
    }

    deinit {
        panel?.delegate = nil
    }

    // MARK: - Binding

    private func bind() {
        bucketStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshActiveBucket() }
            }
            .store(in: &cancellables)

        $content
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self, self.state == .capturing || self.state == .switchingBucket else { return }
                let bucketId = self.activeBucket?.id ?? self.bucketStore.activeBucketId ?? ""
                self.draftStore.scheduleSave(bucketId: bucketId, content: newValue)
                self.cachedDraft = Draft(bucketId: bucketId.isEmpty ? nil : bucketId, content: newValue, updatedAt: Date())
            }
            .store(in: &cancellables)

        refreshActiveBucket()
    }

    private func refreshActiveBucket() {
        if let bid = bucketStore.activeBucketId, let b = bucketStore.buckets.first(where: { $0.id == bid }) {
            activeBucket = b
        } else if let first = bucketStore.buckets.first {
            activeBucket = first
        } else {
            activeBucket = nil
        }
    }

    var activeBucketDisplayName: String {
        activeBucket?.name ?? bucketStore.buckets.first(where: { $0.id == bucketStore.activeBucketId })?.name ?? "Inbox"
    }

    // MARK: - Panel creation

    private func ensurePanel() -> CapturePanel {
        if let p = panel { return p }
        let p = CapturePanel()
        p.delegate = self
        panel = p
        return p
    }

    private func makeHostingView(on screen: NSScreen) -> NSHostingView<CaptureView> {
        let view = CaptureView(controller: self, onContentHeightChanged: { [weak self] height in
            let targetScreen = self?.panel?.screen ?? screen
            self?.panel?.resize(toHeight: height + 32, on: targetScreen, animated: true)
        })
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true
        return hosting
    }

    // MARK: - Toggle / Show / Hide

    func toggle() {
        switch state {
        case .hidden:
            show()
        default:
            hide(preserveDraft: true)
        }
    }

    func show() {
        guard state == .hidden || state == .closing else { return }
        // Capture frontmost app BEFORE activating, so we can restore it on hide.
        if previousApp == nil {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = front
            }
        }
        state = .opening
        saveError = nil

        let screen = ScreenResolver.screenContainingMouse()

        // Restore draft if any (cached, then compat state fallback)
        if let draft = cachedDraft {
            if !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = draft.content
                if let bid = draft.bucketId, !bid.isEmpty, let b = bucketStore.buckets.first(where: { $0.id == bid }) {
                    activeBucket = b
                    bucketStore.setActive(id: b.id)
                }
            }
        } else if !_compatState.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = _compatState.content
        } else if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshActiveBucket()
        }

        let p = ensurePanel()
        let hosting = makeHostingView(on: screen)
        hostingView = hosting
        p.contentView = hosting

        let fitting = hosting.fittingSize
        let desiredHeight = max(CapturePanel.minHeight, min(fitting.height, CapturePanel.maxHeight))
        p.setFrame(ScreenResolver.captureFrame(for: screen, panelHeight: desiredHeight), display: false)

        p.show(on: screen) { [weak self] in
            guard let self else { return }
            self.state = .capturing
            self.focusTextView()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restorePreviousApp() {
        guard let app = previousApp else { return }
        previousApp = nil
        DispatchQueue.main.async {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    func hide(preserveDraft: Bool) {
        guard state != .hidden && state != .closing else { return }
        if preserveDraft {
            state = .preservingDraft
            let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? ""
            do {
                try draftStore.saveImmediately(bucketId: bucketId, content: content)
                cachedDraft = Draft(bucketId: bucketId.isEmpty ? nil : bucketId, content: content, updatedAt: Date())
            } catch {
                debugPrint("[CaptureController] preserveDraft save failed: \(error)")
            }
            _compatState.content = content
            _compatState.selectedBucketId = bucketId.isEmpty ? nil : bucketId
        } else {
            state = .discarding
        }
        state = .closing
        draftStore.cancelPendingSave()
        guard let p = panel else {
            state = .hidden
            NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
            restorePreviousApp()
            return
        }
        p.hideWithAnimation { [weak self] in
            guard let self else { return }
            if !preserveDraft {
                self.draftStore.clear()
                self.cachedDraft = nil
                self.content = ""
                self._compatState.content = ""
            }
            self.state = .hidden
            NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
            self.restorePreviousApp()
        }
    }

    // MARK: - SaveDraft (AppDelegate compat)

    func saveDraft() {
        let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && _compatState.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let toSave = !content.isEmpty ? content : _compatState.content
        try? draftStore.saveImmediately(bucketId: bucketId, content: toSave)
        cachedDraft = Draft(bucketId: bucketId.isEmpty ? nil : bucketId, content: toSave, updatedAt: Date())
    }

    // MARK: - Save

    func save() {
        let raw = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? content : _compatState.content
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let bucketId = activeBucket?.id ?? bucketStore.activeBucketId else {
            saveError = "No bucket selected"
            return
        }
        state = .saving
        saveError = nil
        do {
            try createDump(bucketId: bucketId, content: trimmed)
            draftStore.clear()
            cachedDraft = nil
            content = ""
            _compatState.content = ""
            NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
            let p = panel
            p?.hideWithAnimation { [weak self] in
                self?.state = .hidden
                NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
                self?.restorePreviousApp()
            }
            if p == nil {
                state = .hidden
                restorePreviousApp()
            }
        } catch {
            saveError = error.localizedDescription
            state = .capturing
        }
    }

    private func createDump(bucketId: String, content: String) throws {
        let repo = DumpRepository()
        _ = try repo.createWithTransaction(content: content, bucketId: bucketId, clearDraft: true)
    }

    // MARK: - Discard

    func discard() {
        draftStore.clear()
        cachedDraft = nil
        content = ""
        _compatState.content = ""
        saveError = nil
        hide(preserveDraft: false)
    }

    // MARK: - Cycle Bucket

    func cycleBucket() {
        state = .switchingBucket
        bucketStore.cycleToNext()
        refreshActiveBucket()
        let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? ""
        draftStore.scheduleSave(bucketId: bucketId, content: content)
        cachedDraft = Draft(bucketId: bucketId.isEmpty ? nil : bucketId, content: content, updatedAt: Date())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if self.state == .switchingBucket { self.state = .capturing }
            self.focusTextView()
        }
    }

    // MARK: - Key Handling

    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        let isShift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: discard(); return true
        case 48 where isShift: cycleBucket(); return true
        case 36, 76:
            if isShift { return false }
            save(); return true
        default: return false
        }
    }

    // MARK: - Focus

    private func focusTextView() {
        guard let p = panel else { return }
        DispatchQueue.main.async {
            if let tv = self.findTextView(in: p.contentView) {
                p.makeFirstResponder(tv)
                self.textViewRef = tv
            } else {
                p.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let tv2 = self.findTextView(in: p.contentView) { p.makeFirstResponder(tv2) }
                }
            }
        }
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews { if let f = findTextView(in: sub) { return f } }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {}

    // MARK: - Panel cancel

    private func observePanelCancel() {
        NotificationCenter.default.addObserver(forName: .capturePanelDidCancel, object: nil, queue: .main) { [weak self] _ in
            self?.discard()
        }
    }
}

// MARK: - CaptureStateCompat (AppDelegate expects an object with content + selectedBucketId)

final class CaptureStateCompat: ObservableObject {
    @Published var content: String = ""
    @Published var selectedBucketId: String?
    var isValid: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
