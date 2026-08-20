import AppKit

enum ScreenResolver {
    static let panelWidth: CGFloat = DumpsMetrics.captureWidth
    static let panelTopInset: CGFloat = 8

    static func screenContainingMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(loc) { return screen }
        if let main = NSScreen.main { return main }
        if let first = NSScreen.screens.first { return first }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    static var activeScreen: NSScreen? { screenContainingMouse() }
    static var mainScreen: NSScreen? { NSScreen.main }
    static var panelCenter: NSPoint {
        let s = activeScreen ?? NSScreen.main; guard let screen = s else { return .zero }
        return NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    static func captureFrame(for screen: NSScreen, panelHeight: CGFloat = 56) -> NSRect {
        let width = panelWidth
        let height = panelHeight
        let visibleTop = screen.visibleFrame.maxY
        let frameTop = screen.frame.maxY
        let notchGap: CGFloat
        if visibleTop < frameTop - 2 {
            notchGap = 6
        } else {
            notchGap = panelTopInset
        }
        let y = min(visibleTop, frameTop) - height - notchGap + (visibleTop < frameTop ? 0 : 0)
        let actualY = screen.frame.maxY - height - (visibleTop < frameTop ? 6 : panelTopInset)
        let x = screen.frame.midX - width / 2
        return NSRect(x: x, y: actualY, width: width, height: height)
    }

    static func isNotchedScreen(_ screen: NSScreen) -> Bool {
        screen.visibleFrame.maxY < screen.frame.maxY - 2
    }
}
