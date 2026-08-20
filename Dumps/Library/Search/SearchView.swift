import SwiftUI
import AppKit

struct SearchBarView: View {
    @Binding var query: String
    @FocusState var isFocused: Bool
    @Environment(\.colorScheme) private var scheme

    init(query: Binding<String>, isFocused: FocusState<Bool>) { self._query = query; self._isFocused = isFocused }
    init(query: Binding<String>) { self._query = query; self._isFocused = FocusState() }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textQuaternary(for: scheme)).accessibilityHidden(true)
            TextField("Search dumps…", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary(for: scheme))
                .focused($isFocused).onSubmit {}
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.textTertiary(for: scheme))
                }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.raised(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isFocused ? Theme.violet : Theme.hairlineBorder(for: scheme),
                    lineWidth: isFocused ? 1 : DumpsMetrics.hairline
                )
        )
        .shadow(color: isFocused ? Theme.violet.opacity(0.12) : Color.clear, radius: 6, y: 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct SearchView: View { @Binding var query: String; var body: some View { SearchBarView(query: $query) } }

#if DEBUG
struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) { SearchBarView(query: .constant("")); SearchBarView(query: .constant("hello")) }.padding().frame(width: 360)
    }
}
#endif
