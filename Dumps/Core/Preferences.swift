import Foundation
import Combine
import ServiceManagement

enum Appearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private let userDefaults: UserDefaults

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let globalShortcutKeyCode = "globalShortcutKeyCode"
        static let globalShortcutModifiers = "globalShortcutModifiers"
        static let appearance = "appearance"
        static let showMenuBarIcon = "showMenuBarIcon"
    }

    @Published var launchAtLogin: Bool {
        didSet {
            // Sync with SMAppService; only persist on success.
            if #available(macOS 13.0, *) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
                } catch {
                    debugPrint("[Preferences] SMAppService toggle failed: \(error)")
                    // Revert on failure without re-triggering didSet loop
                    if launchAtLogin != oldValue {
                        DispatchQueue.main.async { [weak self] in
                            self?.launchAtLogin = oldValue
                        }
                    }
                }
            } else {
                userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            }
        }
    }

    @Published var globalShortcutKeyCode: Int {
        didSet { userDefaults.set(globalShortcutKeyCode, forKey: Keys.globalShortcutKeyCode) }
    }

    @Published var globalShortcutModifiers: Int {
        didSet { userDefaults.set(globalShortcutModifiers, forKey: Keys.globalShortcutModifiers) }
    }

    @Published var appearance: String {
        didSet {
            let normalized = appearance.lowercased()
            if normalized != appearance {
                appearance = normalized
                return
            }
            userDefaults.set(normalized, forKey: Keys.appearance)
        }
    }

    var appearanceEnum: Appearance {
        get { Appearance(rawValue: appearance.lowercased()) ?? .system }
        set { appearance = newValue.rawValue }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { userDefaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let defaults = userDefaults

        // launchAtLogin: reflect actual system state on macOS 13+
        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            self.launchAtLogin = enabled
            // Persist the ground-truth so legacy fallback stays consistent
            defaults.set(enabled, forKey: Keys.launchAtLogin)
        } else {
            if defaults.object(forKey: Keys.launchAtLogin) != nil {
                self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
            } else {
                self.launchAtLogin = false
            }
        }

        if defaults.object(forKey: Keys.globalShortcutKeyCode) != nil {
            self.globalShortcutKeyCode = defaults.integer(forKey: Keys.globalShortcutKeyCode)
        } else {
            self.globalShortcutKeyCode = 49
        }

        if defaults.object(forKey: Keys.globalShortcutModifiers) != nil {
            self.globalShortcutModifiers = defaults.integer(forKey: Keys.globalShortcutModifiers)
        } else {
            self.globalShortcutModifiers = 1 << 19
        }

        if let saved = defaults.string(forKey: Keys.appearance), ["system", "light", "dark"].contains(saved.lowercased()) {
            self.appearance = saved.lowercased()
        } else {
            self.appearance = "system"
        }

        if defaults.object(forKey: Keys.showMenuBarIcon) != nil {
            self.showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        } else {
            self.showMenuBarIcon = true
        }
    }

    /// Re-read the actual SMAppService status and update the published value.
    func syncLaunchAtLoginFromSystem() {
        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            if enabled != launchAtLogin {
                launchAtLogin = enabled
            }
            userDefaults.set(enabled, forKey: Keys.launchAtLogin)
        }
    }
}
