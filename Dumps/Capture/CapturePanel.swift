import AppKit
import SwiftUI

/// Borderless floating panel that hosts the capture UI at the top-center of the screen.
final class CapturePanel: NSPanel {

    // MARK: - Constants

    static let panelWidth: CGFloat = 480
    static let minHeight: CGFloat = 64
    static let maxHeight: CGFloat = 260
    static let topInset: CGFloat = 8
    static let animationDuration: TimeInterval = 0.12

    // MARK: - Init

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.minHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        level = .popUpMenu // appears above full-screen windows; .floating is alternative
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        alphaValue = 0

        // Ensure the panel can host SwiftUI content with rounded corners via its contentView.
        contentView?.wantsLayer = true
    }

    // MARK: - Key / Main

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
    }

    // MARK: - Positioning

    /// Positions the panel at the top-center of the given screen.
    func positionOnScreen(_ screen: NSScreen) {
        let frame = ScreenResolver.captureFrame(for: screen, panelHeight: frame.height)
        setFrame(frame, display: false)
    }

    /// Positions with explicit height, clamped to min/max.
    func positionOnScreen(_ screen: NSScreen, height: CGFloat) {
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        let frame = ScreenResolver.captureFrame(for: screen, panelHeight: clamped)
        setFrame(frame, display: false)
    }

    // MARK: - Show / Hide

    /// Shows the panel on the given screen with a fade + slide animation.
    func show(on screen: NSScreen, completion: (() -> Void)? = nil) {
        let targetFrame = ScreenResolver.captureFrame(for: screen, panelHeight: frame.height)

        // Start from slightly above (slide down) and transparent.
        var startFrame = targetFrame
        startFrame.origin.y += 8
        setFrame(startFrame, display: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }, completionHandler: {
            completion?()
        })
    }

    /// Hides the panel with a fade + slide animation, then orders out.
    func hideWithAnimation(completion: (() -> Void)? = nil) {
        var endFrame = frame
        endFrame.origin.y += 6

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            self.orderOut(nil)
            // Reset alpha for next show.
            self.alphaValue = 0
            completion?()
        })
    }

    /// Immediately hides without animation (e.g., for app termination).
    func hideImmediately() {
        alphaValue = 0
        orderOut(nil)
    }

    // MARK: - Sizing

    /// Resizes the panel height to fit content, clamped, with animation.
    func resize(toHeight height: CGFloat, on screen: NSScreen, animated: Bool = true) {
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        let newFrame = ScreenResolver.captureFrame(for: screen, panelHeight: clamped)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    // MARK: - Cancel

    override func cancelOperation(_ sender: Any?) {
        // Esc handling is delegated to CaptureController via keyDown; but handle here as fallback.
        // Find the controller via the content view hosting.
        // Post notification so controller can discard.
        NotificationCenter.default.post(name: .capturePanelDidCancel, object: self)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let capturePanelDidCancel = Notification.Name("capturePanelDidCancel")
}
