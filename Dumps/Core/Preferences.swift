import Foundation
import Combine

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let globalShortcutKeyCode = "globalShortcutKeyCode"
        static let globalShortcutModifiers = "globalShortcutModifiers"
        static let appearance = "appearance"
        static let showMenuBarIcon = "showMenuBarIcon"
    }

    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var globalShortcutKeyCode: Int {
        didSet { UserDefaults.standard.set(globalShortcutKeyCode, forKey: Keys.globalShortcutKeyCode) }
    }

    @Published var globalShortcutModifiers: Int {
        didSet { UserDefaults.standard.set(globalShortcutModifiers, forKey: Keys.globalShortcutModifiers) }
    }

    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: Keys.appearance) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    init(userDefaults: UserDefaults = .standard) {
        let defaults = userDefaults

        if defaults.object(forKey: Keys.launchAtLogin) != nil {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        } else {
            self.launchAtLogin = false
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

        if let saved = defaults.string(forKey: Keys.appearance), ["system", "light", "dark"].contains(saved) {
            self.appearance = saved
        } else {
            self.appearance = "system"
        }

        if defaults.object(forKey: Keys.showMenuBarIcon) != nil {
            self.showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        } else {
            self.showMenuBarIcon = true
        }
    }
}
