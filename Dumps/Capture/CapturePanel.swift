import AppKit
import SwiftUI

final class CapturePanel: NSPanel {
    static let panelWidth: CGFloat = DumpsMetrics.captureWidth
    static let minHeight: CGFloat = 56
    static let maxHeight: CGFloat = 220
    static let topInset: CGFloat = 8
    static let animationDuration: TimeInterval = 0.14

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.minHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear; isOpaque = false; hasShadow = true
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        animationBehavior = .utilityWindow; alphaValue = 0
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func positionOnScreen(_ screen: NSScreen) {
        let frame = ScreenResolver.captureFrame(for: screen, panelHeight: frame.height)
        setFrame(frame, display: false)
    }

    func positionOnScreen(_ screen: NSScreen, height: CGFloat) {
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        let frame = ScreenResolver.captureFrame(for: screen, panelHeight: clamped)
        setFrame(frame, display: false)
    }

    func show(on screen: NSScreen, completion: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setFrame(ScreenResolver.captureFrame(for: screen, panelHeight: frame.height), display: false)
            alphaValue = 1; orderFrontRegardless(); makeKeyAndOrderFront(nil); completion?(); return
        }
        let targetFrame = ScreenResolver.captureFrame(for: screen, panelHeight: frame.height)
        var startFrame = targetFrame; startFrame.origin.y += 8
        setFrame(startFrame, display: false); alphaValue = 0
        orderFrontRegardless(); makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }, completionHandler: { completion?() })
    }

    func hideWithAnimation(completion: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 0; orderOut(nil); completion?(); return
        }
        var endFrame = frame; endFrame.origin.y += 6
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(endFrame, display: true)
        }, completionHandler: { self.orderOut(nil); self.alphaValue = 0; completion?() })
    }

    func hideImmediately() { alphaValue = 0; orderOut(nil) }

    func resize(toHeight height: CGFloat, on screen: NSScreen, animated: Bool = true) {
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        let newFrame = ScreenResolver.captureFrame(for: screen, panelHeight: clamped)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08; ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else { setFrame(newFrame, display: true) }
    }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .capturePanelDidCancel, object: self)
    }
}

extension Notification.Name {
    static let capturePanelDidCancel = Notification.Name("capturePanelDidCancel")
}
