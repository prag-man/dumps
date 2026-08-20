import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var controller: CaptureController
    var onContentHeightChanged: ((CGFloat) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            capsule
            if let error = controller.saveError {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
            }
        }
        .frame(width: DumpsMetrics.captureWidth)
    }

    // MARK: - Silent Lift capsule

    private var capsule: some View {
        HStack(spacing: 10) {
            bucketChip
            Rectangle().fill(Theme.hairlineBorder(for: scheme)).frame(width: 0.5).frame(height: 22)
            CaptureTextView(
                text: $controller.content, placeholder: "Dump it here…",
                isLight: scheme == .light,
                onSave: { controller.save() }, onCycleBucket: { controller.cycleBucket() },
                onDiscard: { controller.discard() }, onContentHeightChanged: onContentHeightChanged
            )
            .frame(minHeight: 20, maxHeight: 140)
            if controller.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("↵").font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary(for: scheme)).opacity(0.7)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DumpsMetrics.captureRadius, style: .continuous)
                .fill(Theme.captureBackground(for: scheme))
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.10), radius: 16, x: 0, y: 8)
                .shadow(color: Theme.violet.opacity(scheme == .dark ? 0.18 : 0.10), radius: 20, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: DumpsMetrics.captureRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DumpsMetrics.captureRadius, style: .continuous)
                .strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DumpsMetrics.captureRadius, style: .continuous)
                .stroke(Theme.violet.opacity(scheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                .blur(radius: 0)
        )
    }

    private var bucketChip: some View {
        Button { controller.cycleBucket() } label: {
            HStack(spacing: 5) {
                Circle().fill(Theme.violet).frame(width: 6, height: 6)
                Text(controller.activeBucketDisplayName)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(Theme.textSecondary(for: scheme))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Theme.raised(for: scheme)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Switch bucket — Shift+Tab")
        .accessibilityLabel("Bucket: \(controller.activeBucketDisplayName)")
        .id(controller.activeBucketDisplayName)
        .transition(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.09), value: controller.activeBucketDisplayName)
    }
}

// MARK: - CaptureTextView

struct CaptureTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder = "Dump something…"
    var isLight: Bool = false
    var onSave: () -> Void
    var onCycleBucket: () -> Void
    var onDiscard: () -> Void
    var onContentHeightChanged: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let tv = InternalTextView()
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.isRichText = false; tv.usesFontPanel = false; tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.backgroundColor = .clear; tv.drawsBackground = false
        tv.isLight = isLight
        tv.insertionPointColor = isLight ? .black : .white
        tv.textColor = isLight ? .black : .white
        tv.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        tv.textContainerInset = NSSize(width: 0, height: 1)
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: DumpsMetrics.captureWidth - 160, height: .greatestFiniteMagnitude)
        tv.textContainer?.lineFragmentPadding = 0
        context.coordinator.placeholder = placeholder
        context.coordinator.isLight = isLight
        context.coordinator.onContentHeightChanged = onContentHeightChanged
        context.coordinator.updatePlaceholderVisibility(for: tv)
        let sv = NSScrollView()
        sv.drawsBackground = false; sv.hasVerticalScroller = false; sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true; sv.borderType = .noBorder
        sv.documentView = tv
        sv.contentView.postsBoundsChangedNotifications = true
        sv.wantsLayer = true; sv.backgroundColor = .clear
        return sv
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? InternalTextView else { return }
        if tv.string != text { tv.string = text; context.coordinator.updatePlaceholderVisibility(for: tv) }
        if context.coordinator.placeholder != placeholder { context.coordinator.placeholder = placeholder; context.coordinator.updatePlaceholderVisibility(for: tv) }
        context.coordinator.isLight = isLight
        tv.isLight = isLight
        tv.insertionPointColor = isLight ? .black : .white
        tv.textColor = isLight ? NSColor.black.withAlphaComponent(0.85) : NSColor.white.withAlphaComponent(0.92)
        for sub in tv.subviews where sub is NSTextField { (sub as? NSTextField)?.textColor = isLight ? NSColor.black.withAlphaComponent(0.30) : NSColor.white.withAlphaComponent(0.32) }
        context.coordinator.onSave = onSave; context.coordinator.onCycleBucket = onCycleBucket
        context.coordinator.onDiscard = onDiscard; context.coordinator.onContentHeightChanged = onContentHeightChanged
        if let window = tv.window, window.isKeyWindow, window.firstResponder !== tv { window.makeFirstResponder(tv) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placeholder: placeholder, isLight: isLight, onSave: onSave, onCycleBucket: onCycleBucket, onDiscard: onDiscard, onContentHeightChanged: onContentHeightChanged)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>; var placeholder: String; var isLight: Bool
        var onSave: () -> Void; var onCycleBucket: () -> Void; var onDiscard: () -> Void
        var onContentHeightChanged: ((CGFloat) -> Void)?
        private var placeholderField: NSTextField?
        init(text: Binding<String>, placeholder: String, isLight: Bool, onSave: @escaping () -> Void, onCycleBucket: @escaping () -> Void, onDiscard: @escaping () -> Void, onContentHeightChanged: ((CGFloat) -> Void)? = nil) {
            self.text = text; self.placeholder = placeholder; self.isLight = isLight
            self.onSave = onSave; self.onCycleBucket = onCycleBucket; self.onDiscard = onDiscard; self.onContentHeightChanged = onContentHeightChanged
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            updatePlaceholderVisibility(for: tv)
            let h: CGFloat
            if let lm = tv.layoutManager, let tc = tv.textContainer { h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2 + 4 }
            else { h = tv.bounds.height }
            onContentHeightChanged?(h)
        }
        func updatePlaceholderVisibility(for textView: NSTextView) {
            if textView.string.isEmpty {
                if placeholderField == nil {
                    let f = NSTextField(labelWithString: placeholder)
                    f.isEditable = false; f.isSelectable = false; f.backgroundColor = .clear
                    f.textColor = (isLight ? NSColor.black : NSColor.white).withAlphaComponent(0.30)
                    f.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
                    f.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(f)
                    NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 0), f.topAnchor.constraint(equalTo: textView.topAnchor, constant: 1)])
                    placeholderField = f
                }
                placeholderField?.isHidden = false
            } else { placeholderField?.isHidden = true }
        }
    }

    class InternalTextView: NSTextView {
        weak var coordinator: Coordinator?
        var isLight: Bool = false
        override func keyDown(with event: NSEvent) {
            let isShift = event.modifierFlags.contains(.shift)
            let isCmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 53: coordinator?.onDiscard(); return
            case 48 where isShift: coordinator?.onCycleBucket(); return
            case 48: super.keyDown(with: event); return
            case 36, 76 where isShift: super.keyDown(with: event); return
            case 36, 76 where isCmd: coordinator?.onSave(); return
            case 36, 76: coordinator?.onSave(); return
            default: super.keyDown(with: event)
            }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) }
        override var acceptsFirstResponder: Bool { true }
    }
}
