import Foundation
import Combine
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ActiveBucketStore: ObservableObject {
    static let shared = ActiveBucketStore()

    @Published var activeBucketId: String?
    @Published var buckets: [Bucket] = []

    private let bucketRepo: BucketRepository
    private let db: DatabaseManager
    private static let userDefaultsKey = "active_bucket_id"
    private static let appStateKey = "active_bucket_id"

    init() {
        self.bucketRepo = BucketRepository()
        self.db = DatabaseManager.shared
        load()
    }

    init(bucketRepo: BucketRepository, databaseManager: DatabaseManager) {
        self.bucketRepo = bucketRepo
        self.db = databaseManager
    }

    static func __test_init(bucketRepo: BucketRepository, db: DatabaseManager) -> ActiveBucketStore {
        ActiveBucketStore(bucketRepo: bucketRepo, databaseManager: db)
    }

    func load() {
        buckets = bucketRepo.listActive()
        var resolved: String?
        let fromState: String? = db.withDB { handle in BucketRepository.appStateValue(key: Self.appStateKey, db: handle) }
        if let v = fromState, !v.isEmpty { resolved = v }
        else if let f = UserDefaults.standard.string(forKey: Self.userDefaultsKey), !f.isEmpty { resolved = f }
        if let rid = resolved {
            if buckets.contains(where: { $0.id == rid }) { activeBucketId = rid } else { fallbackIfNeeded() }
        } else { fallbackIfNeeded() }
        if let c = activeBucketId { persistActiveId(c) }
    }

    func setActive(id: String) {
        guard buckets.contains(where: { $0.id == id }) else { return }
        activeBucketId = id; persistActiveId(id)
    }

    @discardableResult
    func cycleToNext() -> Bucket? {
        buckets = bucketRepo.listActive()
        guard !buckets.isEmpty else { return nil }
        if buckets.count == 1 { let only = buckets[0]; activeBucketId = only.id; persistActiveId(only.id); return only }
        guard let current = activeBucketId, let idx = buckets.firstIndex(where: { $0.id == current }) else {
            let first = buckets[0]; activeBucketId = first.id; persistActiveId(first.id); return first
        }
        let next = buckets[(idx + 1) % buckets.count]
        activeBucketId = next.id; persistActiveId(next.id); return next
    }

    func fallbackIfNeeded() {
        buckets = bucketRepo.listActive()
        if let c = activeBucketId, buckets.contains(where: { $0.id == c }) { return }
        if let first = buckets.first { activeBucketId = first.id; persistActiveId(first.id) }
        else {
            activeBucketId = nil
            db.withDB { handle in
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(handle, "DELETE FROM app_state WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (Self.appStateKey as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt); sqlite3_finalize(stmt)
                }
            }
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        }
    }

    func refreshBuckets() { buckets = bucketRepo.listActive(); fallbackIfNeeded() }

    private func persistActiveId(_ id: String) {
        db.withDB { handle in BucketRepository.setAppState(key: Self.appStateKey, value: id, db: handle) }
        UserDefaults.standard.set(id, forKey: Self.userDefaultsKey)
    }
}
