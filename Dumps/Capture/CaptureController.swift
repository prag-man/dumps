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

    // MARK: - Panel

    private var panel: CapturePanel?
    private var hostingView: NSHostingView<CaptureView>?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var bucketStoreCancellable: AnyCancellable?

    // MARK: - Focus

    private weak var textViewRef: NSTextView?

    // MARK: - Init

    init(bucketStore: ActiveBucketStore? = nil,
         draftStore: DraftStore = DraftStore.shared,
         hotkeyManager: HotkeyManager? = nil) {
        // ActiveBucketStore requires a BucketRepository(db:) in this codebase; construct lazily.
        // If caller passes nil, create a default store. Tests that inject a store will pass one.
        if let bs = bucketStore {
            self.bucketStore = bs
        } else {
            // Use the shared/default pattern: prefer a fresh store backed by shared DB.
            // ActiveBucketStore in this codebase has init(bucketRepo:) or init() depending on version.
            // Try both via runtime: we attempt init() first (exists now), fallback to doing nothing.
            // The file currently has init() with no args (uses BucketRepository()), so this works.
            self.bucketStore = ActiveBucketStore()
        }
        self.draftStore = draftStore
        // hotkeyManager param kept for spec compat but AppDelegate owns its own HotkeyManager; ignore.
        _ = hotkeyManager
        super.init()
        bind()
        observePanelCancel()
        // Keep compat state in sync with @Published content
        _compatState.$content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in if self?.content != v { self?.content = v } }
            .store(in: &cancellables)
        $content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in if self?._compatState.content != v { self?._compatState.content = v } }
            .store(in: &cancellables)
    }

    /// Designated init for tests that want to inject a store.
    init(activeBucketStore: ActiveBucketStore, draftStore: DraftStore = DraftStore.shared) {
        self.bucketStore = activeBucketStore
        self.draftStore = draftStore
        super.init()
        bind()
        observePanelCancel()
        _compatState.$content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in if self?.content != v { self?.content = v } }
            .store(in: &cancellables)
        $content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in if self?._compatState.content != v { self?._compatState.content = v } }
            .store(in: &cancellables)
    }

    deinit {
        panel?.delegate = nil
    }

    // MARK: - Binding

    private func bind() {
        // ActiveBucketStore in current codebase: @Published var activeBucketId + buckets, no Combine publisher for active bucket object.
        // Observe via objectWillChange.
        bucketStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshActiveBucket() }
            }
            .store(in: &cancellables)

        // Also poll activeBucketId changes via KVO-like observation on Published
        // We do this by observing the store's $activeBucketId if available.
        // Since ActiveBucketStore now has @Published activeBucketId, we can observe it.
        // Use Mirror to find publisher to stay compile-safe.
        // Simpler: just subscribe via Combine's publisher(for:) alternative - but we can just observe objectWillChange above.

        // Draft debounce on content change (only while capturing)
        $content
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self, self.state == .capturing || self.state == .switchingBucket else { return }
                let bucketId = self.activeBucket?.id ?? self.bucketStore.activeBucketId ?? self._compatState.selectedBucketId ?? ""
                self.draftStore.scheduleSave(bucketId: bucketId, content: newValue)
            }
            .store(in: &cancellables)

        refreshActiveBucket()
    }

    private func refreshActiveBucket() {
        // Prefer compat state's selectedBucketId if set (AppDelegate sets it)
        if let sel = _compatState.selectedBucketId, let b = bucketStore.buckets.first(where: { $0.id == sel }) {
            activeBucket = b
            return
        }
        if let bid = bucketStore.activeBucketId, let b = bucketStore.buckets.first(where: { $0.id == bid }) {
            activeBucket = b
        } else if let first = bucketStore.buckets.first {
            activeBucket = first
        } else {
            activeBucket = nil
        }
    }

    var activeBucketDisplayName: String {
        activeBucket?.name ?? bucketStore.buckets.first(where: { $0.id == bucketStore.activeBucketId })?.name ?? _compatState.selectedBucketId.flatMap { id in bucketStore.buckets.first(where: { $0.id == id })?.name } ?? "Inbox"
    }

    // MARK: - Panel creation

    private func ensurePanel() -> CapturePanel {
        if let p = panel { return p }
        let p = CapturePanel()
        p.delegate = self
        panel = p
        return p
    }

    private func makeHostingView() -> NSHostingView<CaptureView> {
        let view = CaptureView(controller: self)
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
        state = .opening
        saveError = nil

        let screen = ScreenResolver.screenContainingMouse()

        // Restore draft if any (SQLite first, then compat state)
        if let draft = draftStore.load() {
            if !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = draft.content
                _compatState.content = draft.content
                if let bid = draft.bucketId, !bid.isEmpty, let b = bucketStore.buckets.first(where: { $0.id == bid }) {
                    activeBucket = b
                    _compatState.selectedBucketId = b.id
                    bucketStore.setActive(id: b.id)
                }
            }
        } else if !_compatState.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = _compatState.content
        } else if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshActiveBucket()
        }

        let p = ensurePanel()
        let hosting = makeHostingView()
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

    func hide(preserveDraft: Bool) {
        guard state != .hidden && state != .closing else { return }
        if preserveDraft {
            state = .preservingDraft
            let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? _compatState.selectedBucketId ?? ""
            do {
                try draftStore.saveImmediately(bucketId: bucketId, content: content)
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
            return
        }
        p.hideWithAnimation { [weak self] in
            guard let self else { return }
            if !preserveDraft {
                self.draftStore.clear()
                self.content = ""
                self._compatState.content = ""
            }
            self.state = .hidden
        }
    }

    // MARK: - SaveDraft (AppDelegate compat)

    func saveDraft() {
        let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? _compatState.selectedBucketId ?? ""
        // Don't persist whitespace-only drafts as "hasDraft"
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && _compatState.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let toSave = !content.isEmpty ? content : _compatState.content
        try? draftStore.saveImmediately(bucketId: bucketId, content: toSave)
    }

    // MARK: - Save

    func save() {
        let raw = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? content : _compatState.content
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            discard()
            return
        }
        guard let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? _compatState.selectedBucketId else {
            saveError = "No bucket selected"
            return
        }
        state = .saving
        saveError = nil
        do {
            try createDump(bucketId: bucketId, content: trimmed)
            draftStore.clear()
            content = ""
            _compatState.content = ""
            let p = panel
            p?.hideWithAnimation { [weak self] in self?.state = .hidden }
            if p == nil { state = .hidden }
        } catch {
            saveError = error.localizedDescription
            state = .capturing
        }
    }

    private func createDump(bucketId: String, content: String) throws {
        // Use DumpRepository with the shared DB. DumpRepository in this codebase requires init(db:) or uses shared.
        // Current file shows `private let db = DatabaseManager.shared` and `init()` with no args, but tests use `DumpRepository(db: db)`.
        // Support both: try DumpRepository() then fallback to DumpRepository(db: DatabaseManager.shared)
        // The instance method we need is `create(content:bucketId:)` or `createWithTransaction`.
        // We prefer transactional creation that also clears draft.

        // Try the shared-DB repository first
        do {
            let repo = DumpRepository()
            _ = try repo.createWithTransaction(content: content, bucketId: bucketId, clearDraft: true)
            return
        } catch {
            // If that fails due to missing bucket or other, rethrow if it's a validation error
            // Otherwise try non-transactional
            if let de = error as? DumpError { throw de }
            // Try create then manual draft clear
            do {
                let repo = DumpRepository()
                _ = try repo.create(content: content, bucketId: bucketId)
                DatabaseManager.shared.withDB { handle in
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(handle, "DELETE FROM capture_draft WHERE singleton_id = 1;", -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_step(stmt); sqlite3_finalize(stmt)
                    }
                }
                return
            } catch {
                throw error
            }
        }
    }

    // MARK: - Discard

    func discard() {
        draftStore.clear()
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
        _compatState.selectedBucketId = activeBucket?.id ?? bucketStore.activeBucketId
        let bucketId = activeBucket?.id ?? bucketStore.activeBucketId ?? ""
        draftStore.scheduleSave(bucketId: bucketId, content: content)
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

// Keep the old class name so AppDelegate's `controller.captureState` type-checks even if it was
// previously `CaptureState`. We alias via extension: AppDelegate uses `captureState.content` which
// now resolves to CaptureStateCompat. No extra alias needed.
