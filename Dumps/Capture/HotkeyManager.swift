import AppKit
import Carbon

/// Global hotkey manager using Carbon `RegisterEventHotKey` with an NSEvent fallback.
/// Supports both the spec API (register(keyCode:modifiers:) -> Bool, isRegistered, onHotkey)
/// and the AppDelegate API (register(onTrigger:)).
final class HotkeyManager {

    // MARK: - Spec API

    var onHotkey: (() -> Void)?
    private(set) var isRegistered: Bool = false
    private(set) var lastError: String?

    static let defaultKeyCode: UInt32 = 49 // Space
    static let defaultModifiers: UInt32 = 2048 // optionKey
    static let cmdKeyModifier: UInt32 = 256
    static let optionKeyModifier: UInt32 = 2048
    static let controlKeyModifier: UInt32 = 4096
    static let shiftKeyModifier: UInt32 = 512

    // MARK: - AppDelegate compat

    var keyCode: Int {
        get { UserDefaults.standard.object(forKey: "globalShortcutKeyCode") as? Int ?? 49 }
        set { UserDefaults.standard.set(newValue, forKey: "globalShortcutKeyCode") }
    }
    var modifiers: UInt32 {
        get { UInt32(UserDefaults.standard.object(forKey: "globalShortcutModifiers") as? Int ?? Int(Self.defaultModifiers)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "globalShortcutModifiers") }
    }

    // MARK: - Private

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x44554D50), id: 1) // 'DUMP'
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fallbackKeyCode: UInt32 = defaultKeyCode
    private var fallbackModifiers: NSEvent.ModifierFlags = .option
    private var onTrigger: (() -> Void)?

    deinit { unregister() }

    // MARK: - Register (spec)

    @discardableResult
    func register(keyCode: UInt32 = defaultKeyCode, modifiers: UInt32 = defaultModifiers) -> Bool {
        unregister()
        lastError = nil
        fallbackKeyCode = keyCode
        fallbackModifiers = carbonModifiersToCocoa(modifiers)
        if registerViaCarbon(keyCode: keyCode, modifiers: modifiers) {
            isRegistered = true
            return true
        }
        debugPrint("[HotkeyManager] Carbon failed: \(lastError ?? "unknown"), fallback to NSEvent")
        registerViaFallback(keyCode: keyCode)
        isRegistered = true
        return true
    }

    // MARK: - Register (AppDelegate)

    func register(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        self.onHotkey = onTrigger
        // Use stored UserDefaults values
        let kc = UInt32(keyCode)
        let mods = modifiers
        register(keyCode: kc, modifiers: mods)
    }

    // Legacy: register() with no args using UserDefaults values
    func register() {
        let kc = UInt32(keyCode)
        let mods = modifiers
        register(keyCode: kc, modifiers: mods)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h = eventHandlerRef { RemoveEventHandler(h); eventHandlerRef = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        isRegistered = false
    }

    // MARK: - Carbon

    private func registerViaCarbon(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let inst = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let cb = inst.onTrigger ?? inst.onHotkey
            if Thread.isMainThread { cb?() } else { DispatchQueue.main.async { cb?() } }
            return noErr
        }
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let inst = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, ptr, &handlerRef)
        guard inst == noErr else { lastError = "InstallEventHandler failed: \(inst)"; return false }
        eventHandlerRef = handlerRef
        var hkRef: EventHotKeyRef?
        let reg = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hkRef)
        guard reg == noErr, let ref = hkRef else {
            lastError = "RegisterEventHotKey failed: \(reg)"
            if let h = handlerRef { RemoveEventHandler(h); eventHandlerRef = nil }
            return false
        }
        hotKeyRef = ref
        return true
    }

    private func registerViaFallback(keyCode: UInt32) {
        let targetFlags = fallbackModifiers
        let targetCode = UInt16(keyCode)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == targetCode && event.modifierFlags.intersection([.command, .option, .control, .shift]) == targetFlags {
                let cb = self.onTrigger ?? self.onHotkey
                DispatchQueue.main.async { cb?() }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == targetCode && event.modifierFlags.intersection([.command, .option, .control, .shift]) == targetFlags {
                let cb = self.onTrigger ?? self.onHotkey
                DispatchQueue.main.async { cb?() }
                return nil
            }
            return event
        }
        if globalMonitor == nil && localMonitor == nil { lastError = "Failed to install NSEvent monitors" }
    }

    private func carbonModifiersToCocoa(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbon & 256 != 0 { f.insert(.command) }
        if carbon & 2048 != 0 { f.insert(.option) }
        if carbon & 4096 != 0 { f.insert(.control) }
        if carbon & 512 != 0 { f.insert(.shift) }
        return f
    }
}
