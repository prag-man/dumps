import SwiftUI

struct DumpRowView: View {
    let dump: Dump
    let bucket: Bucket?
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var onMove: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var editedContent = ""
    @State private var isHovering = false
    @State private var bucketsForMove: [Bucket] = []
    @FocusState private var editorFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private var timeString: String { Self.timeFormatter.string(from: dump.createdAt) }

    var body: some View {
        Group { if isEditing { editorView } else { rowView } }
            .onAppear { editedContent = dump.content }
            .onChange(of: dump.content) { _, new in if !isEditing { editedContent = new } }
    }

    private var rowView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(timeString)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary(for: scheme))
                        .monospacedDigit()
                    if let bucket {
                        Text(bucket.name.uppercased())
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.textTertiary(for: scheme))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.raised(for: scheme)))
                            .overlay(Capsule().strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: DumpsMetrics.hairline))
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
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary(for: scheme))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.raised(for: scheme)))
                                .overlay(Circle().strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: DumpsMetrics.hairline))
                        }
                        .menuStyle(.borderlessButton).fixedSize().help("More actions")
                        .transition(.opacity)
                        .onAppear { loadBucketsForMove() }
                    }
                }

                Text(dump.content)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textPrimary(for: scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous))
            .onTapGesture { onSelect?() }
            .onTapGesture(count: 2) { beginEditing() }

            Rectangle()
                .fill(Theme.hairlineBorder(for: scheme))
                .frame(height: DumpsMetrics.hairline)
                .padding(.leading, 12)
                .opacity(isEditing ? 0 : 1)
        }
        .onHover { h in isHovering = h; if h { loadBucketsForMove() } }
        .contextMenu {
            Button("Edit") { beginEditing() }
            Menu("Move to Bucket") { ForEach(bucketsForMove, id: \.id) { b in Button(b.name) { onMove?(b.id) }.disabled(b.id == dump.bucketId) } }
            Divider(); Button("Delete", role: .destructive) { onDelete?() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.selected(for: scheme) }
        if isHovering { return Theme.hover(for: scheme) }
        return Color.clear
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editedContent)
                .font(.system(size: 13)).lineSpacing(3)
                .foregroundStyle(Theme.textPrimary(for: scheme))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 220)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                        .fill(Theme.raised(for: scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                        .strokeBorder(Theme.violet.opacity(isEditing ? 0.55 : 0.3), lineWidth: isEditing ? 1 : DumpsMetrics.hairline)
                )
                .focused($editorFocused).onAppear { editorFocused = true }
            HStack(spacing: 8) {
                Button("Cancel") { cancelEditing() }.keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary(for: scheme))
                Spacer()
                Button("Save") { saveEditing() }.keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.violet)
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                .fill(Theme.hover(for: scheme).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                .strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: DumpsMetrics.hairline)
        )
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
        return VStack(spacing: 0) { DumpRowView(dump: d, bucket: b); DumpRowView(dump: d, bucket: nil) }.padding().frame(width: 520)
    }
}
#endif
