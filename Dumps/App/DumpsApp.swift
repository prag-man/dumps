import SwiftUI

@main
struct DumpsApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var preferences = Preferences.shared
    @StateObject private var activeBucketStore = ActiveBucketStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(preferences)
                .environmentObject(activeBucketStore)
                .preferredColorScheme(appearanceScheme)
                .frame(minWidth: 760, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Dump") { appDelegate.captureController?.show() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Search") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .preferredColorScheme(appearanceScheme)
        }

        MenuBarExtra("Dumps", systemImage: "tray.full") {
            Button("Open Dumps") {
                NSApp.activate(ignoringOtherApps: true)
                for w in NSApp.windows where w.canBecomeKey { w.makeKeyAndOrderFront(nil); break }
            }
            Button("New Dump") { appDelegate.captureController?.show() }
            Divider()
            if let bid = activeBucketStore.activeBucketId,
               let b = activeBucketStore.buckets.first(where: { $0.id == bid }) {
                Text("Active: \(b.name)").foregroundStyle(.secondary)
            }
            Toggle("Launch at Login", isOn: $preferences.launchAtLogin)
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Dumps") { NSApp.terminate(nil) }
        }
    }

    private var appearanceScheme: ColorScheme? {
        switch preferences.appearance.lowercased() {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
}
