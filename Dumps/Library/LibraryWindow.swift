import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let dumpsDidChange = Notification.Name("DumpsDidChange")
}

struct LibraryView: View {
    @State private var selectedBucketId: String? = nil
    @State private var searchQuery = ""
    @State private var isSettingsPresented = false
    @StateObject private var activeBucketStore = ActiveBucketStore.shared
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedBucketId: $selectedBucketId, activeBucketStore: activeBucketStore)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            FeedView(selectedBucketId: $selectedBucketId, searchQuery: $searchQuery)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SearchBarView(query: $searchQuery, isFocused: _searchFocused)
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 400)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isSettingsPresented = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .regular))
                }
                .help("Settings")
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(scheme == .dark ? 0.55 : 0.5))
            }
        }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden())
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView().frame(width: 480, height: 360)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
        .background(scheme == .dark ? Theme.background : Color(nsColor: .windowBackgroundColor))
    }
}

final class LibraryWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Dumps"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("LibraryWindow")
        window.contentView = NSHostingView(rootView: LibraryView())
        window.contentMinSize = NSSize(width: 760, height: 500)
        self.init(window: window)
        window.makeKeyAndOrderFront(nil)
    }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider { static var previews: some View { LibraryView() } }
#endif
