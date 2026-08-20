import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            bucketIndicator.padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 7)
            CaptureTextView(
                text: $controller.content, placeholder: "Dump something…",
                onSave: { controller.save() }, onCycleBucket: { controller.cycleBucket() },
                onDiscard: { controller.discard() }, onContentHeightChanged: { _ in }
            )
            .frame(minHeight: 28, maxHeight: 180).padding(.horizontal, 16).padding(.bottom, 12)
            if let error = controller.saveError {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            hintBar.padding(.horizontal, 16).padding(.bottom, 10)
        }
        .frame(width: ScreenResolver.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel)
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var bucketIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Text(controller.activeBucketDisplayName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.68))
            Spacer()
            Text("⇧ Tab").font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.32))
        }
    }

    private var hintBar: some View {
        HStack(spacing: 12) {
            hintLabel("↵", "save"); hintLabel("⇧↵", "newline"); hintLabel("Esc", "discard"); Spacer()
        }
    }
    private func hintLabel(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(action).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

struct CaptureTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder = "Dump something…"
    var onSave: () -> Void
    var onCycleBucket: () -> Void
    var onDiscard: () -> Void
    var onContentHeightChanged: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InternalTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .white
        textView.textColor = .white
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: ScreenResolver.panelWidth - 32, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.placeholder = placeholder
        context.coordinator.updatePlaceholderVisibility(for: textView)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.wantsLayer = true
        scrollView.backgroundColor = .clear
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? InternalTextView else { return }
        if tv.string != text { tv.string = text; context.coordinator.updatePlaceholderVisibility(for: tv) }
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            context.coordinator.updatePlaceholderVisibility(for: tv)
        }
        context.coordinator.onSave = onSave
        context.coordinator.onCycleBucket = onCycleBucket
        context.coordinator.onDiscard = onDiscard
        if let window = tv.window, window.isKeyWindow, window.firstResponder !== tv {
            window.makeFirstResponder(tv)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placeholder: placeholder, onSave: onSave, onCycleBucket: onCycleBucket, onDiscard: onDiscard)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var placeholder: String
        var onSave: () -> Void
        var onCycleBucket: () -> Void
        var onDiscard: () -> Void
        private var placeholderField: NSTextField?
        init(text: Binding<String>, placeholder: String, onSave: @escaping () -> Void, onCycleBucket: @escaping () -> Void, onDiscard: @escaping () -> Void) {
            self.text = text; self.placeholder = placeholder; self.onSave = onSave; self.onCycleBucket = onCycleBucket; self.onDiscard = onDiscard
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            updatePlaceholderVisibility(for: tv)
        }
        func updatePlaceholderVisibility(for textView: NSTextView) {
            let isEmpty = textView.string.isEmpty
            if isEmpty {
                if placeholderField == nil {
                    let field = NSTextField(labelWithString: placeholder)
                    field.isEditable = false; field.isSelectable = false
                    field.backgroundColor = .clear
                    field.textColor = NSColor.white.withAlphaComponent(0.32)
                    field.font = NSFont.systemFont(ofSize: 15, weight: .regular)
                    field.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(field)
                    NSLayoutConstraint.activate([
                        field.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 0),
                        field.topAnchor.constraint(equalTo: textView.topAnchor, constant: 2)
                    ])
                    placeholderField = field
                }
                placeholderField?.isHidden = false
            } else { placeholderField?.isHidden = true }
        }
    }

    class InternalTextView: NSTextView {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags; let isShift = flags.contains(.shift); let isCmd = flags.contains(.command)
            let keyCode = event.keyCode
            if keyCode == 53 { coordinator?.onDiscard(); return }
            if keyCode == 48 { if isShift { coordinator?.onCycleBucket(); return }; super.keyDown(with: event); return }
            if keyCode == 36 || keyCode == 76 {
                if isShift { super.keyDown(with: event); return }
                else if isCmd { coordinator?.onSave(); return }
                else { coordinator?.onSave(); return }
            }
            super.keyDown(with: event)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) }
        override var acceptsFirstResponder: Bool { true }
    }
}
