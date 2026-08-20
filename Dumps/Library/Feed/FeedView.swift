import SwiftUI
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var dayGroups: [DayGroup] = []
    @Published var isLoading = false
    @Published var bucketsById: [String: Bucket] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let dumpRepo = DumpRepository()
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
        isLoading = true; refreshBuckets()
        let q = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = (q?.isEmpty == true) ? nil : q
        dayGroups = dumpRepo.fetchGroupedFeed(bucketId: bucketId, searchQuery: query)
        isLoading = false
    }
    func updateDump(id: String, content: String) { try? dumpRepo.update(id: id, content: content); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
    func moveDump(id: String, toBucket bucketId: String) { try? dumpRepo.move(id: id, bucketId: bucketId); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
    func deleteDump(id: String) { try? dumpRepo.softDelete(id: id); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
}

struct FeedView: View {
    @Binding var selectedBucketId: String?
    @Binding var searchQuery: String
    @StateObject private var vm = FeedViewModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group { if vm.dayGroups.isEmpty && !vm.isLoading { emptyState } else { feedScroll } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(scheme == .dark ? Theme.background : Color(nsColor: .textBackgroundColor))
            .onAppear { vm.load(bucketId: selectedBucketId, searchQuery: searchQuery) }
            .onChange(of: selectedBucketId) { _, new in vm.load(bucketId: new, searchQuery: searchQuery) }
            .onChange(of: searchQuery) { _, new in vm.load(bucketId: selectedBucketId, searchQuery: new) }
            .onReceive(NotificationCenter.default.publisher(for: .dumpsDidChange)) { _ in vm.load(bucketId: selectedBucketId, searchQuery: searchQuery) }
            .overlay { if vm.isLoading && vm.dayGroups.isEmpty { ProgressView().controlSize(.small).tint(Theme.textTertiary) } }
    }

    private var feedScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(vm.dayGroups) { group in daySection(group) }
            }
            .padding(.horizontal, 20).padding(.vertical, 20)
        }
        .scrollIndicators(.automatic)
    }

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(group.dayLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textTertiary)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.dumps) { dump in
                    DumpRowView(
                        dump: dump, bucket: vm.bucketsById[dump.bucketId],
                        onEdit: { vm.updateDump(id: dump.id, content: $0) },
                        onMove: { vm.moveDump(id: dump.id, toBucket: $0) },
                        onDelete: { vm.deleteDump(id: dump.id) }
                    )
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
