import XCTest
@testable import Dumps
import Foundation
import SQLite3

// MARK: - Test-only extensions to make repos testable with injected DB

extension DatabaseManager {
    static func inMemory() -> DatabaseManager { DatabaseManager.__test_inMemory() }
    func execute(_ sql: String) { try? withDB { h in try execOn(h, sql: sql) } }
}

extension Migrations {
    static func run(db: DatabaseManager) {
        db.withDB { handle in try? Migrations.runMigrations(db: handle) }
    }
}

extension BucketRepository {
    func fetchAllBuckets() -> [Bucket] { list() }
    func fetchAllBuckets(includeArchived: Bool) -> [Bucket] { includeArchived ? list() : listActive() }
    func bucketSoftDelete(id: String) -> Bool { _ = try? archive(id: id); return find(id: id) != nil }
    func bucketRestore(id: String) -> Bool { _ = try? unarchive(id: id); return true }
}

private func makeBucket(in db: DatabaseManager, name: String, sortOrder: Int = 0) -> Bucket {
    let repo = BucketRepository(db: db)
    if let b = try? repo.create(name: name) {
        if b.sortOrder != sortOrder {
            db.execute("UPDATE buckets SET sort_order = \(sortOrder) WHERE id = '\(b.id)';")
            return Bucket(id: b.id, name: b.name, sortOrder: sortOrder, createdAt: b.createdAt, updatedAt: b.updatedAt, archivedAt: b.archivedAt)
        }
        return b
    }
    let bucket = Bucket(name: name, sortOrder: sortOrder)
    BucketRepository.insertForTest(bucket: bucket, db: db)
    return bucket
}

private func makeDump(in db: DatabaseManager, bucketId: String, content: String, createdAt: Date = Date()) -> Dump {
    let dump = Dump(bucketId: bucketId, content: content, createdAt: createdAt, updatedAt: createdAt)
    DumpRepository.insertForTest(dump: dump, db: db)
    return dump
}

extension Dump {
    var isValid: Bool { !isWhitespaceOnly }
}

extension DumpRepository {
    func fetchAllDumps() -> [Dump] { fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil) }
    func fetchAllDumpsIncludingDeleted() -> [Dump] {
        var out: [Dump] = []
        DatabaseManager.__test_lastDB?.withDB { handle in
            var stmt: OpaquePointer?
            let sql = "SELECT id, bucket_id, content, created_at, updated_at, deleted_at FROM dumps ORDER BY created_at DESC;"
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { if let d = DumpRepository.dumpFromRow(stmt!) { out.append(d) } }
        }
        return out
    }
    func fetchDump(id: String) -> Dump? {
        fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil).first { $0.id == id }
            ?? fetchAllDumpsIncludingDeleted().first { $0.id == id }
    }
    func testSoftDelete(id: String) -> Bool { (try? softDelete(id: id) as Void) != nil }
    func testRestore(id: String) -> Bool { (try? restore(id: id) as Void) != nil }
    func updateContent(id: String, content: String) -> Bool { (try? update(id: id, content: content)) != nil }
    func moveToBucket(id: String, toBucketId bucketId: String) -> Bool { (try? move(id: id, bucketId: bucketId)) != nil }
}

extension DayGroup {
    static func group(_ dumps: [Dump]) -> [DayGroup] { grouped(from: dumps) }
    var date: Date { day }
}

// MARK: - Tests

final class DumpsTests: XCTestCase {
    var db: DatabaseManager!
    override func setUp() {
        super.setUp()
        db = DatabaseManager.inMemory()
        Migrations.run(db: db)
        db.execute("DELETE FROM dumps; DELETE FROM buckets;")
        DatabaseManager.__test_lastDB = db
    }
    override func tearDown() { db.close(); super.tearDown() }

    func testBucketCreationAndDuplicateRejection() {
        let repo = BucketRepository(db: db)
        let first = try? repo.create(name: "Work")
        XCTAssertNotNil(first); XCTAssertEqual(first?.name, "Work")
        XCTAssertNil(try? repo.create(name: "Work"))
        XCTAssertNil(try? repo.create(name: "work"))
        XCTAssertNil(try? repo.create(name: "WORK"))
        XCTAssertNil(try? repo.create(name: "   "))
        XCTAssertNil(try? repo.create(name: ""))
        XCTAssertNotNil(try? repo.create(name: "Personal"))
    }

    func testBucketReordering() {
        let repo = BucketRepository(db: db)
        let a = makeBucket(in: db, name: "A", sortOrder: 0)
        let b = makeBucket(in: db, name: "B", sortOrder: 1)
        let c = makeBucket(in: db, name: "C", sortOrder: 2)
        try? repo.reorder(ids: [c.id, a.id, b.id])
        let ordered = repo.fetchAllBuckets()
        XCTAssertEqual(ordered.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(ordered[0].sortOrder, 0)
        XCTAssertEqual(ordered[1].sortOrder, 1)
        XCTAssertEqual(ordered[2].sortOrder, 2)
    }

    func testActiveBucketFallback() {
        let repo = BucketRepository(db: db)
        let inbox = makeBucket(in: db, name: "Inbox", sortOrder: 0)
        let work = makeBucket(in: db, name: "Work", sortOrder: 1)

        UserDefaults.standard.removeObject(forKey: "active_bucket_id")
        // Inject test DB via shared hack — use bucketRepo init with db
        let store = ActiveBucketStore.__test_init(bucketRepo: repo, db: db)
        store.load()
        XCTAssertNotNil(store.activeBucketId)
        XCTAssertEqual(store.activeBucketId, inbox.id)

        try? repo.archive(id: inbox.id)
        let fallbackStore = ActiveBucketStore.__test_init(bucketRepo: repo, db: db)
        fallbackStore.activeBucketId = inbox.id
        fallbackStore.fallbackIfNeeded()
        XCTAssertEqual(fallbackStore.activeBucketId, work.id)

        db.execute("DELETE FROM buckets;")
        let emptyStore = ActiveBucketStore.__test_init(bucketRepo: repo, db: db)
        emptyStore.activeBucketId = inbox.id
        emptyStore.load()
        XCTAssertNil(emptyStore.activeBucketId)
    }

    func testDumpValidation() {
        let bucket = makeBucket(in: db, name: "Inbox")
        let repo = DumpRepository(db: db)
        XCTAssertNil(try? repo.create(content: "", bucketId: bucket.id))
        XCTAssertNil(try? repo.create(content: "   ", bucketId: bucket.id))
        XCTAssertNil(try? repo.create(content: "\n\t  \n", bucketId: bucket.id))
        XCTAssertNotNil(try? repo.create(content: "hello world", bucketId: bucket.id))
        XCTAssertFalse(Dump(bucketId: bucket.id, content: "   ").isValid)
        XCTAssertTrue(Dump(bucketId: bucket.id, content: " real ").isValid)
        if let valid = try? repo.create(content: "to update", bucketId: bucket.id) {
            XCTAssertFalse((try? repo.update(id: valid.id, content: "   ")) != nil)
        }
    }

    func testDumpFeedOrdering() {
        let bucket = makeBucket(in: db, name: "Inbox")
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        _ = makeDump(in: db, bucketId: bucket.id, content: "oldest", createdAt: twoDaysAgo)
        _ = makeDump(in: db, bucketId: bucket.id, content: "newest", createdAt: now)
        _ = makeDump(in: db, bucketId: bucket.id, content: "middle", createdAt: yesterday)
        let all = DumpRepository(db: db).fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].content, "newest")
        XCTAssertEqual(all[1].content, "middle")
        XCTAssertEqual(all[2].content, "oldest")
        let groups = DayGroup.group(all)
        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups[0].day > groups[1].day)
        db.execute("DELETE FROM dumps;")
        let sameDay = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)
        let sameDay2 = Calendar.current.startOfDay(for: now).addingTimeInterval(7200)
        _ = makeDump(in: db, bucketId: bucket.id, content: "a", createdAt: sameDay)
        _ = makeDump(in: db, bucketId: bucket.id, content: "b", createdAt: sameDay2)
        let sameDayDumps = DumpRepository(db: db).fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil)
        let sameDayGroups = DayGroup.group(sameDayDumps)
        XCTAssertEqual(sameDayGroups.count, 1)
        XCTAssertEqual(sameDayGroups[0].dumps.count, 2)
    }

    func testSoftDeleteAndRestore() {
        let bucket = makeBucket(in: db, name: "Inbox")
        let dump = makeDump(in: db, bucketId: bucket.id, content: "to delete")
        let repo = DumpRepository(db: db)
        let direct = repo.fetchDump(id: dump.id)
        XCTAssertNil(direct?.deletedAt)
        XCTAssertTrue(repo.testSoftDelete(id: dump.id))
        let afterDelete = DatabaseManager.__test_lastDB?.withDB { handle -> Dump? in
            var stmt: OpaquePointer?
            let sql = "SELECT id, bucket_id, content, created_at, updated_at, deleted_at FROM dumps WHERE id = ?;"
            sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (dump.id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW, let d = DumpRepository.dumpFromRow(stmt!) else { return nil }
            return d
        } ?? nil
        XCTAssertNotNil(afterDelete?.deletedAt)
        XCTAssertTrue(DumpRepository(db: db).fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil).isEmpty)
        XCTAssertTrue(repo.testRestore(id: dump.id))
        let afterRestore = DatabaseManager.__test_lastDB?.withDB { handle -> Dump? in
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(handle, "SELECT id, bucket_id, content, created_at, updated_at, deleted_at FROM dumps WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (dump.id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return DumpRepository.dumpFromRow(stmt!)
        } ?? nil
        XCTAssertNil(afterRestore?.deletedAt)
        XCTAssertEqual(DumpRepository(db: db).fetchFeed(bucketId: nil, searchQuery: nil, limit: nil, offset: nil).count, 1)
    }

    func testDraftLifecycle() {
        let store = DraftStore.shared
        store.clear()
        XCTAssertFalse(store.hasDraft)
        store.save(content: "draft text", bucketId: "bucket-123")
        XCTAssertTrue(store.hasDraft)
        XCTAssertEqual(store.load().content, "draft text")
        XCTAssertEqual(store.load().bucketId, "bucket-123")
        store.save(content: "updated draft", bucketId: String?.none)
        XCTAssertEqual(store.load().content, "updated draft")
        XCTAssertNil(store.load().bucketId)
        store.clear()
        XCTAssertFalse(store.hasDraft)
        store.save(content: "   \n  ", bucketId: String?.none)
        XCTAssertFalse(store.hasDraft)
        store.clear()
    }

    func testSearchFiltering() {
        let bucketA = makeBucket(in: db, name: "BucketA", sortOrder: 0)
        let bucketB = makeBucket(in: db, name: "BucketB", sortOrder: 1)
        _ = makeDump(in: db, bucketId: bucketA.id, content: "hello world")
        _ = makeDump(in: db, bucketId: bucketA.id, content: "goodbye world")
        _ = makeDump(in: db, bucketId: bucketB.id, content: "hello there")
        let repo = DumpRepository(db: db)
        XCTAssertEqual(repo.fetchFeed(bucketId: nil, searchQuery: "hello", limit: nil, offset: nil).count, 2)
        XCTAssertEqual(repo.fetchFeed(bucketId: nil, searchQuery: "HELLO", limit: nil, offset: nil).count, 2)
        let scoped = repo.fetchFeed(bucketId: bucketA.id, searchQuery: "hello", limit: nil, offset: nil)
        XCTAssertEqual(scoped.count, 1); XCTAssertEqual(scoped.first?.content, "hello world")
        XCTAssertTrue(repo.fetchFeed(bucketId: nil, searchQuery: "xyz_no_match", limit: nil, offset: nil).isEmpty)
        // Deleted excluded
        if let toDelete = repo.fetchFeed(bucketId: nil, searchQuery: "goodbye", limit: nil, offset: nil).first {
            try? repo.softDelete(id: toDelete.id)
        }
        XCTAssertTrue(repo.fetchFeed(bucketId: nil, searchQuery: "goodbye", limit: nil, offset: nil).isEmpty)
    }

    func testMoveDumpPreservesCreatedAt() {
        let bucketA = makeBucket(in: db, name: "BucketA", sortOrder: 0)
        let bucketB = makeBucket(in: db, name: "BucketB", sortOrder: 1)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let dump = makeDump(in: db, bucketId: bucketA.id, content: "movable", createdAt: originalDate)
        XCTAssertEqual(dump.createdAt.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(DumpRepository(db: db).moveToBucket(id: dump.id, toBucketId: bucketB.id))
        let fetched: Dump? = DatabaseManager.__test_lastDB?.withDB { handle -> Dump? in
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(handle, "SELECT id, bucket_id, content, created_at, updated_at, deleted_at FROM dumps WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (dump.id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return DumpRepository.dumpFromRow(stmt!)
        } ?? nil
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.bucketId, bucketB.id)
        XCTAssertEqual(fetched?.createdAt.timeIntervalSince1970 ?? 0, originalDate.timeIntervalSince1970, accuracy: 1)
    }
}
