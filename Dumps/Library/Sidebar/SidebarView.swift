import SwiftUI
import Combine

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var buckets: [Bucket] = []
    @Published var counts: [String: Int] = [:]
    var activeBuckets: [Bucket] { buckets.filter { !$0.isArchived } }
    var archivedBuckets: [Bucket] { buckets.filter { $0.isArchived } }
    private var cancellables = Set<AnyCancellable>()
    private let bucketRepo = BucketRepository()
    private let dumpRepo = DumpRepository()
    init() {
        NotificationCenter.default.publisher(for: .dumpsDidChange).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
    }
    func refresh() { buckets = bucketRepo.list(); counts = dumpRepo.countByBucket() }
    func createBucket(name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        _ = try? bucketRepo.create(name: t); refresh()
        NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
    }
    func renameBucket(id: String, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        try? bucketRepo.rename(id: id, name: t); refresh()
        NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
    }
    func archiveBucket(id: String) { try? bucketRepo.archive(id: id); refresh(); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
    func unarchiveBucket(id: String) { try? bucketRepo.unarchive(id: id); refresh(); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
    func deleteBucket(id: String) {
        guard (counts[id] ?? 0) == 0 else { return }
        try? bucketRepo.deleteIfEmpty(id: id); refresh()
        NotificationCenter.default.post(name: .dumpsDidChange, object: nil)
    }
}

struct SidebarView: View {
    @Binding var selectedBucketId: String?
    @ObservedObject var activeBucketStore: ActiveBucketStore
    @StateObject private var vm = SidebarViewModel()
    @State private var showNewBucketAlert = false
    @State private var newBucketName = ""
    @State private var renameTarget: Bucket?
    @State private var renameName = ""
    @State private var showRenameAlert = false
    @State private var showArchived = false
    @State private var deleteConfirmBucket: Bucket?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List(selection: $selectedBucketId) {
            Section {
                Text("Feed")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary(for: scheme))
                    .tag(Optional<String>.none)
                    .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
            } header: {
                Text("Feed")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }

            Section {
                ForEach(vm.activeBuckets, id: \.id) { bucket in
                    bucketRow(bucket).tag(Optional(bucket.id))
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                }
            } header: {
                Text("BUCKETS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }

            if !vm.archivedBuckets.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(vm.archivedBuckets, id: \.id) { bucket in
                            bucketRow(bucket).tag(Optional(bucket.id))
                                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        }
                    } label: {
                        Label("Archived", systemImage: "archivebox").font(.system(size: 11)).foregroundStyle(Theme.textSecondary(for: scheme))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar(for: scheme))
        .safeAreaInset(edge: .bottom) {
            Button { showNewBucketAlert = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                    Text("New bucket").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised(for: scheme)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: DumpsMetrics.hairline))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sidebar(for: scheme).opacity(0.98))
            .overlay(Rectangle().fill(Theme.hairlineBorder(for: scheme)).frame(height: DumpsMetrics.hairline), alignment: .top)
        }
        .onAppear { vm.refresh(); activeBucketStore.buckets = vm.activeBuckets }
        .onReceive(NotificationCenter.default.publisher(for: .dumpsDidChange)) { _ in vm.refresh(); activeBucketStore.buckets = vm.activeBuckets }
        .onChange(of: vm.buckets) { _, new in activeBucketStore.buckets = new.filter { !$0.isArchived } }
        .alert("New bucket", isPresented: $showNewBucketAlert) {
            TextField("Name", text: $newBucketName)
            Button("Cancel", role: .cancel) { newBucketName = "" }
            Button("Create") { vm.createBucket(name: newBucketName); newBucketName = "" }
                .disabled(newBucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Enter a name for the new bucket.") }
        .alert("Rename bucket", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { renameTarget = nil; renameName = "" }
            Button("Rename") {
                if let t = renameTarget { vm.renameBucket(id: t.id, to: renameName) }
                renameTarget = nil; renameName = ""
            }.disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Enter a new name.") }
        .alert("Delete bucket?", isPresented: Binding(get: { deleteConfirmBucket != nil }, set: { if !$0 { deleteConfirmBucket = nil } })) {
            Button("Cancel", role: .cancel) { deleteConfirmBucket = nil }
            Button("Delete", role: .destructive) {
                if let b = deleteConfirmBucket { vm.deleteBucket(id: b.id) }; deleteConfirmBucket = nil
            }
        } message: {
            if let b = deleteConfirmBucket { Text("\"\(b.name)\" is empty and will be permanently deleted.") }
        }
    }

    private func bucketRow(_ bucket: Bucket) -> some View {
        HStack(spacing: 6) {
            if activeBucketStore.activeBucketId == bucket.id {
                Circle().fill(Theme.violet).frame(width: 6, height: 6)
                    .help("Active capture bucket").accessibilityLabel("Active")
            } else {
                Circle().fill(Color.clear).frame(width: 6, height: 6)
            }
            Text(bucket.name).font(.system(size: 12.5, weight: .regular)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(Theme.textPrimary(for: scheme).opacity(0.88))
            Spacer(minLength: 4)
            if let count = vm.counts[bucket.id], count > 0 {
                Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.raised(for: scheme)))
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !bucket.isArchived {
                Button("Use for Capture") { activeBucketStore.setActive(id: bucket.id); NotificationCenter.default.post(name: .dumpsDidChange, object: nil) }
            }
            Button("Rename") { renameTarget = bucket; renameName = bucket.name; showRenameAlert = true }
            Divider()
            if bucket.isArchived { Button("Unarchive") { vm.unarchiveBucket(id: bucket.id) } }
            else { Button("Archive") { vm.archiveBucket(id: bucket.id) } }
            if (vm.counts[bucket.id] ?? 0) == 0 { Button("Delete", role: .destructive) { deleteConfirmBucket = bucket } }
        }
    }
}

#if DEBUG
struct SidebarView_Previews: PreviewProvider {
    static var previews: some View { SidebarView(selectedBucketId: .constant(nil), activeBucketStore: ActiveBucketStore()).frame(width: 220, height: 500) }
}
#endif
