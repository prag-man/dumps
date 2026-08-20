import SwiftUI

@main
struct DumpsApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var preferences = Preferences.shared
    @StateObject private var activeBucketStore = ActiveBucketStore.shared

    var body: some Scene {
        // Library is lazily managed by AppDelegate.LibraryWindowController

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .preferredColorScheme(appearanceScheme)
        }
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
