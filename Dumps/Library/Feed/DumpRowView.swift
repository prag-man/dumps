import SwiftUI

struct DumpRowView: View {
    let dump: Dump
    let bucket: Bucket?
    var onEdit: ((String) -> Void)? = nil
    var onMove: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var editedContent = ""
    @State private var isHovering = false
    @State private var bucketsForMove: [Bucket] = []
    @FocusState private var editorFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB"); return f
    }()

    var body: some View {
        Group { if isEditing { editorView } else { rowView } }
            .onAppear { editedContent = dump.content }
            .onChange(of: dump.content) { _, new in if !isEditing { editedContent = new } }
    }

    private var rowView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(timeFormatter.string(from: dump.createdAt))
                    .font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                if let bucket {
                    Text(bucket.name.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isHovering {
                    Menu {
                        Button("Edit") { beginEditing() }
                        Menu("Move to Bucket") {
                            ForEach(bucketsForMove, id: \.id) { b in Button(b.name) { onMove?(b.id) }.disabled(b.id == dump.bucketId) }
                        }
                        Divider(); Button("Delete", role: .destructive) { onDelete?() }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton).fixedSize().help("More actions")
                    .onAppear { loadBucketsForMove() }
                }
            }
            Text(dump.content)
                .font(.system(size: 13, weight: .regular)).lineSpacing(3).foregroundStyle(scheme == .dark ? Theme.textPrimary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(isHovering ? 0.055 : 0.035) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(scheme == .dark ? Theme.separator : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { h in isHovering = h; if h { loadBucketsForMove() } }
        .contextMenu {
            Button("Edit") { beginEditing() }
            Menu("Move to Bucket") { ForEach(bucketsForMove, id: \.id) { b in Button(b.name) { onMove?(b.id) }.disabled(b.id == dump.bucketId) } }
            Divider(); Button("Delete", role: .destructive) { onDelete?() }
        }
        .onTapGesture(count: 2) { beginEditing() }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editedContent)
                .font(.system(size: 13)).lineSpacing(3)
                .foregroundStyle(scheme == .dark ? Theme.textPrimary : Color.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 220).padding(6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.06) : Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                .focused($editorFocused).onAppear { editorFocused = true }
            HStack(spacing: 8) {
                Button("Cancel") { cancelEditing() }.keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Save") { saveEditing() }.keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.accent)
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 12))
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.04) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private func beginEditing() { editedContent = dump.content; isEditing = true }
    private func cancelEditing() { editedContent = dump.content; isEditing = false }
    private func saveEditing() {
        guard !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onEdit?(editedContent); isEditing = false
    }
    private func loadBucketsForMove() { bucketsForMove = BucketRepository().listActive() }
}

#if DEBUG
struct DumpRowView_Previews: PreviewProvider {
    static var previews: some View {
        let b = Bucket(name: "Ideas", sortOrder: 0)
        let d = Dump(bucketId: b.id, content: "Remember to look into SwiftData vs GRDB for persistence.")
        return VStack(spacing: 12) { DumpRowView(dump: d, bucket: b); DumpRowView(dump: d, bucket: nil) }.padding().frame(width: 520)
    }
}
#endif
