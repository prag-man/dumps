import SwiftUI
import AppKit

// MARK: - DumpEditorView (thin wrapper — canonical editor is InlineDumpEditor below)

/// Editor for a single dump. Supports both inline and sheet presentation.
/// - Validation: non-whitespace required
/// - Keyboard: Cmd+Enter saves, Esc cancels
struct DumpEditorView: View {
    let dump: Dump
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(dump: Dump, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.dump = dump
        self.onSave = onSave
        self.onCancel = onCancel
        self._text = State(initialValue: dump.content)
    }

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Dump")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            InlineDumpEditor(
                text: $text,
                onSave: { if isValid { onSave(text) } },
                onCancel: { onCancel() }
            )
        }
        .padding(16)
        .frame(minWidth: 360)
        .onAppear { focused = true }
    }
}

// MARK: - InlineDumpEditor (canonical)

/// Lightweight inline editor surface — the single source of truth for dump editing.
struct InlineDumpEditor: View {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write something…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 220)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    .focused($focused)
            }
            .onAppear { focused = true }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save") { if isValid { onSave() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isValid)
            }
            .font(.system(size: 12))
        }
    }
}

// MARK: - Sheet container

struct DumpEditorSheet: View {
    let dump: Dump
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DumpEditorView(
            dump: dump,
            onSave: { newText in
                onSave(newText)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

#if DEBUG
struct DumpEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let dump = Dump(bucketId: "b1", content: "Hello world")
        return DumpEditorView(dump: dump, onSave: { _ in }, onCancel: {})
            .frame(width: 420)
    }
}
#endif
