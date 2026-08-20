import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum BucketError: Error, LocalizedError {
    case emptyName
    case duplicate(String)
    case notFound
    case cannotArchiveLastBucket
    case cannotDeleteNonEmpty
    case cannotDeleteWithDumps
    var errorDescription: String? {
        switch self {
        case .emptyName: return "Bucket name cannot be empty."
        case .duplicate(let n): return "A bucket named \"\(n)\" already exists."
        case .notFound: return "Bucket not found."
        case .cannotArchiveLastBucket: return "Cannot archive the last remaining bucket."
        case .cannotDeleteNonEmpty: return "Cannot delete a bucket that still contains dumps."
        case .cannotDeleteWithDumps: return "Cannot delete a bucket that still contains dumps."
        }
    }
}

final class BucketRepository {
    private let db: DatabaseManager
    init(db: DatabaseManager = DatabaseManager.shared) { self.db = db }
    static func insertForTest(bucket: Bucket, db: DatabaseManager) { try? db.withDB { h in try Self.insert(bucket: bucket, db: h) } }

    func list() -> [Bucket] { db.withDB { handle in Self.fetchAll(db: handle, whereClause: nil) } }
    func listActive() -> [Bucket] { db.withDB { handle in Self.fetchAll(db: handle, whereClause: "archived_at IS NULL") } }

    func find(id: String) -> Bucket? {
        db.withDB { handle in
            Self.fetchAll(db: handle, whereClause: "id = ?") { stmt in
                sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            }.first
        }
    }

    func create(name: String) throws -> Bucket {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BucketError.emptyName }
        return try db.withDB { handle in
            if Self.exists(name: trimmed, db: handle) { throw BucketError.duplicate(trimmed) }
            let now = Date()
            let bucket = Bucket(id: UUID().uuidString, name: trimmed, sortOrder: Self.nextSortOrder(db: handle), createdAt: now, updatedAt: now, archivedAt: nil)
            try Self.insert(bucket: bucket, db: handle)
            return bucket
        }
    }

    func rename(id: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BucketError.emptyName }
        try db.withDB { handle in
            guard Self.fetchAll(db: handle, whereClause: "id = ?", bind: { stmt in sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT) }).first != nil else { throw BucketError.notFound }
            if Self.exists(name: trimmed, excludingId: id, db: handle) { throw BucketError.duplicate(trimmed) }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE buckets SET name = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (trimmed as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
        }
    }

    func reorder(ids: [String]) throws {
        try db.inTransaction { handle in
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE buckets SET sort_order = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            for (index, bid) in ids.enumerated() {
                sqlite3_reset(stmt); sqlite3_clear_bindings(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(index))
                sqlite3_bind_int64(stmt, 2, nowMs)
                sqlite3_bind_text(stmt, 3, (bid as NSString).utf8String, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            }
        }
    }

    func archive(id: String) throws {
        try db.inTransaction { handle in
            guard let bucket = Self.fetchAll(db: handle, whereClause: "id = ?", bind: { stmt in sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT) }).first else { throw BucketError.notFound }
            if bucket.isArchived { return }
            if Self.countActive(db: handle) <= 1 { throw BucketError.cannotArchiveLastBucket }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE buckets SET archived_at = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs); sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            if let activeId = Self.appStateValue(key: "active_bucket_id", db: handle), activeId == id {
                let remaining = Self.fetchAll(db: handle, whereClause: "archived_at IS NULL")
                if let fallback = remaining.first { Self.setAppState(key: "active_bucket_id", value: fallback.id, db: handle); UserDefaults.standard.set(fallback.id, forKey: "active_bucket_id") }
            }
        }
    }

    func unarchive(id: String) throws {
        try db.withDB { handle in
            guard Self.fetchAll(db: handle, whereClause: "id = ?", bind: { stmt in sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT) }).first != nil else { throw BucketError.notFound }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE buckets SET archived_at = NULL, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs); sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
        }
    }

    func deleteIfEmpty(id: String) throws {
        try db.withDB { handle in
            guard Self.fetchAll(db: handle, whereClause: "id = ?", bind: { stmt in sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT) }).first != nil else { throw BucketError.notFound }
            if Self.dumpCount(bucketId: id, db: handle) > 0 { throw BucketError.cannotDeleteNonEmpty }
            let sql = "DELETE FROM buckets WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
        }
    }

    static func fetchAll(db: OpaquePointer, whereClause: String?, bind: ((OpaquePointer) -> Void)? = nil) -> [Bucket] {
        var sql = "SELECT id, name, sort_order, created_at, updated_at, archived_at FROM buckets"
        if let clause = whereClause { sql += " WHERE \(clause)" }
        sql += " ORDER BY sort_order ASC;"
        return fetchBuckets(db: db, sql: sql, bind: bind)
    }
    static func fetchAll(db: OpaquePointer, whereClause: String) -> [Bucket] { fetchAll(db: db, whereClause: whereClause, bind: nil) }

    private static func fetchBuckets(db: OpaquePointer, sql: String, bind: ((OpaquePointer) -> Void)?) -> [Bucket] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let bind { bind(stmt!) }
        var buckets: [Bucket] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let b = bucketFromRow(stmt!) { buckets.append(b) } }
        return buckets
    }

    static func bucketFromRow(_ stmt: OpaquePointer) -> Bucket? {
        guard let idC = sqlite3_column_text(stmt, 0), let nameC = sqlite3_column_text(stmt, 1) else { return nil }
        let id = String(cString: idC); let name = String(cString: nameC)
        let sortOrder = Int(sqlite3_column_int64(stmt, 2))
        let createdAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 3)) / 1000.0)
        let updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 4)) / 1000.0)
        let archivedAt: Date? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5)) / 1000.0) : nil
        return Bucket(id: id, name: name, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt, archivedAt: archivedAt)
    }

    static func exists(name: String, db: OpaquePointer) -> Bool { exists(name: name, excludingId: nil, db: db) }
    static func exists(name: String, excludingId: String?, db: OpaquePointer) -> Bool {
        var sql = "SELECT COUNT(*) FROM buckets WHERE name = ? COLLATE NOCASE"
        if excludingId != nil { sql += " AND id != ?" }
        sql += ";"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let ex = excludingId { sqlite3_bind_text(stmt, 2, (ex as NSString).utf8String, -1, SQLITE_TRANSIENT) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int64(stmt, 0) > 0
    }
    static func nextSortOrder(db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM buckets;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    static func countActive(db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM buckets WHERE archived_at IS NULL;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    static func dumpCount(bucketId: String, db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM dumps WHERE bucket_id = ?;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (bucketId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    static func insert(bucket: Bucket, db: OpaquePointer) throws {
        let sql = "INSERT INTO buckets (id, name, sort_order, created_at, updated_at, archived_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: sql) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (bucket.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (bucket.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, Int64(bucket.sortOrder))
        sqlite3_bind_int64(stmt, 4, Int64(bucket.createdAt.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 5, Int64(bucket.updatedAt.timeIntervalSince1970 * 1000))
        if let a = bucket.archivedAt { sqlite3_bind_int64(stmt, 6, Int64(a.timeIntervalSince1970 * 1000)) } else { sqlite3_bind_null(stmt, 6) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: sql) }
    }
    static func appStateValue(key: String, db: OpaquePointer) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM app_state WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }
    static func setAppState(key: String, value: String, db: OpaquePointer) {
        let sql = "INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
}
