import SwiftUI
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var dayGroups: [DayGroup] = []
    @Published var isLoading = false
    @Published var bucketsById: [String: Bucket] = [:]
    @Published var errorMessage: String?
    @Published var undoDumpId: String?
    @Published var undoBucketId: String?
    private var cancellables = Set<AnyCancellable>()
    private let dumpRepo = DumpRepository()
    private var undoTimer: Timer?
    private var loadTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.publisher(for: .dumpsDidChange).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBuckets() }.store(in: &cancellables)
        refreshBuckets()
    }

    func refreshBuckets() {
        let buckets = BucketRepository().list()
        bucketsById = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
    }

    func load(bucketId: String?, searchQuery: String?) {
        isLoading = true
        refreshBuckets()
        let q = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = (q?.isEmpty == true) ? nil : q
        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [dumpRepo] in
            let groups = dumpRepo.fetchGroupedFeed(bucketId: bucketId, searchQuery: query)
            await MainActor.run {
                // Only apply if this is still the active task
                self.dayGroups = groups
                self.isLoading = false
            }
        }
    }

    func updateDump(id: String, content: String) {
        do { try dumpRepo.update(id: id, content: content); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) } catch { errorMessage = error.localizedDescription }
    }

    func moveDump(id: String, toBucket bucketId: String) {
        do { try dumpRepo.move(id: id, bucketId: bucketId); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) } catch { errorMessage = error.localizedDescription }
    }

    func deleteDump(id: String) {
        let dumpBeforeDelete: Dump? = dumpRepo.fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil).first(where: { $0.id == id })
        let bucketId = dumpBeforeDelete?.bucketId
        do {
            try dumpRepo.softDelete(id: id)
            undoTimer?.invalidate()
            undoDumpId = id
            undoBucketId = bucketId
            undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.clearUndo() }
            }
            NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard let id = undoDumpId else { return }
        undoTimer?.invalidate()
        do {
            try dumpRepo.restore(id: id)
            clearUndo()
            NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearUndo() {
        undoTimer?.invalidate()
        undoTimer = nil
        undoDumpId = nil
        undoBucketId = nil
    }
}

struct FeedView: View {
    @Binding var selectedBucketId: String?
    @Binding var searchQuery: String
    @StateObject private var vm = FeedViewModel()
    @State private var debouncedQuery = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedDumpId: String?
    @Environment(\.colorScheme) private var scheme

    private var flattenedDumpIds: [String] {
        vm.dayGroups.flatMap { $0.dumps.map(\.id) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group { if vm.dayGroups.isEmpty && !vm.isLoading { emptyState } else { feedScroll } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Theme.background : Color(nsColor: .textBackgroundColor))
                .focusable()
                .onMoveCommand { direction in
                    guard !flattenedDumpIds.isEmpty else { return }
                    switch direction {
                    case .up:
                        if let cur = selectedDumpId, let idx = flattenedDumpIds.firstIndex(of: cur), idx > 0 {
                            selectedDumpId = flattenedDumpIds[idx - 1]
                        } else {
                            selectedDumpId = flattenedDumpIds.first
                        }
                    case .down:
                        if let cur = selectedDumpId, let idx = flattenedDumpIds.firstIndex(of: cur), idx < flattenedDumpIds.count - 1 {
                            selectedDumpId = flattenedDumpIds[idx + 1]
                        } else {
                            selectedDumpId = flattenedDumpIds.last
                        }
                    default: break
                    }
                }
                .onDeleteCommand {
                    if let id = selectedDumpId { vm.deleteDump(id: id) }
                }

            if vm.undoDumpId != nil {
                undoBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.undoDumpId)
        .onAppear { debouncedQuery = searchQuery; vm.load(bucketId: selectedBucketId, searchQuery: searchQuery) }
        .onChange(of: selectedBucketId) { _, new in vm.load(bucketId: new, searchQuery: debouncedQuery) }
        .onChange(of: searchQuery) { _, new in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = new
                vm.load(bucketId: selectedBucketId, searchQuery: new)
            }
        }
        .onChange(of: debouncedQuery) { _, new in
            // load already triggered in debounce task
        }
        .onReceive(NotificationCenter.default.publisher(for: .dumpsDidChange)) { _ in vm.load(bucketId: selectedBucketId, searchQuery: debouncedQuery) }
        .overlay { if vm.isLoading && vm.dayGroups.isEmpty { ProgressView().controlSize(.small).tint(Theme.textTertiary) } }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            if let msg = vm.errorMessage { Text(msg) }
        }
    }

    private var undoBanner: some View {
        HStack(spacing: 12) {
            Text("Dump deleted").font(.system(size: 12.5)).foregroundStyle(scheme == .dark ? Theme.textPrimary : Color.primary)
            Spacer()
            Button("Undo") { vm.undo() }
                .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(scheme == .dark ? Theme.backgroundElevated : Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var feedScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(vm.dayGroups) { group in daySection(group) }
                }
                .padding(.horizontal, 20).padding(.vertical, 20)
            }
            .scrollIndicators(.automatic)
            .onAppear {
                DispatchQueue.main.async {
                    if let first = vm.dayGroups.first?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(first, anchor: .top) }
                    }
                    if let lastId = vm.dayGroups.first?.dumps.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.dayGroups) { _, new in
                // On initial load or when groups first populate, land near newest
                if let firstGroup = new.first, let lastDumpId = firstGroup.dumps.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(firstGroup.id, anchor: .top)
                        proxy.scrollTo(lastDumpId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(group.dayLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textTertiary)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }
            .id(group.id)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.dumps) { dump in
                    DumpRowView(
                        dump: dump, bucket: vm.bucketsById[dump.bucketId],
                        isSelected: selectedDumpId == dump.id,
                        onSelect: { selectedDumpId = dump.id },
                        onEdit: { vm.updateDump(id: dump.id, content: $0) },
                        onMove: { vm.moveDump(id: dump.id, toBucket: $0) },
                        onDelete: { vm.deleteDump(id: dump.id) }
                    )
                    .id(dump.id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.textQuaternary)
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing dumped yet.").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text("Press ⌥Space from anywhere.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            } else {
                Text("No results for \"\(searchQuery)\"").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text("Try a different search term.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).multilineTextAlignment(.center).padding(32)
    }
}

#if DEBUG
struct FeedView_Previews: PreviewProvider { static var previews: some View { FeedView(selectedBucketId: .constant(nil), searchQuery: .constant("")).frame(width: 640, height: 500) } }
#endif
