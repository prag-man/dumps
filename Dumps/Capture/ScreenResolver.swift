import AppKit

/// Resolves the screen that should host the capture panel and computes its frame.
enum ScreenResolver {

    static let panelWidth: CGFloat = 480
    static let panelTopInset: CGFloat = 8

    /// Returns the screen that currently contains the mouse pointer.
    /// Falls back to `NSScreen.main` or the first available screen.
    static func screenContainingMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        // NSEvent.mouseLocation and NSScreen.frame share the same coordinate space
        // (origin at bottom-left, Quartz coordinates). No flipping needed.
        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            return screen
        }
        if let main = NSScreen.main { return main }
        if let first = NSScreen.screens.first { return first }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    /// Convenience accessor for the active screen (used by some callers).
    static var activeScreen: NSScreen? {
        screenContainingMouse()
    }

    static var mainScreen: NSScreen? {
        NSScreen.main
    }

    static var panelCenter: NSPoint {
        let screen = activeScreen ?? NSScreen.main
        guard let s = screen else { return .zero }
        return NSPoint(x: s.frame.midX, y: s.frame.midY)
    }

    /// Returns the frame for the capture panel positioned at the top-center of the given screen.
    /// Uses `screen.frame` (not `visibleFrame`) so the panel sits at the physical top edge,
    /// visually merging with the notch/menu-bar area.
    /// - Parameters:
    ///   - screen: The screen to position on.
    ///   - panelHeight: The current height of the panel.
    static func captureFrame(for screen: NSScreen, panelHeight: CGFloat = 64) -> NSRect {
        let width: CGFloat = panelWidth
        let height: CGFloat = panelHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height - panelTopInset
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
