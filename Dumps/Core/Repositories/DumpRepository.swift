import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DumpError: Error, LocalizedError {
    case emptyContent, notFound, bucketNotFound
    var errorDescription: String? {
        switch self {
        case .emptyContent: return "Dump content cannot be empty."
        case .notFound: return "Dump not found."
        case .bucketNotFound: return "Target bucket not found."
        }
    }
}

final class DumpRepository {
    private let db: DatabaseManager
    init(db: DatabaseManager = DatabaseManager.shared) { self.db = db }
    static func insertForTest(dump: Dump, db: DatabaseManager) { try? db.withDB { h in try Self.insert(dump: dump, db: h) } }

    func create(content: String, bucketId: String) throws -> Dump {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DumpError.emptyContent }
        return try db.withDB { handle in
            let now = Date()
            let dump = Dump(id: UUID().uuidString, bucketId: bucketId, content: content, createdAt: now, updatedAt: now, deletedAt: nil)
            try Self.insert(dump: dump, db: handle)
            return dump
        }
    }

    func createWithTransaction(content: String, bucketId: String, clearDraft: Bool) throws -> Dump {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DumpError.emptyContent }
        var result: Dump!
        try db.inTransaction { handle in
            let now = Date()
            let dump = Dump(id: UUID().uuidString, bucketId: bucketId, content: content, createdAt: now, updatedAt: now, deletedAt: nil)
            try Self.insert(dump: dump, db: handle)
            if clearDraft { var s: OpaquePointer?; if sqlite3_prepare_v2(handle, "DELETE FROM capture_draft WHERE singleton_id = 1;", -1, &s, nil) == SQLITE_OK { sqlite3_step(s); sqlite3_finalize(s) } }
            result = dump
        }
        return result
    }

    func update(id: String, content: String) throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DumpError.emptyContent }
        try db.withDB { handle in
            guard Self.exists(id: id, db: handle) else { throw DumpError.notFound }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE dumps SET content = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (content as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, nowMs); sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
        }
    }

    func move(id: String, bucketId: String) throws {
        try db.withDB { handle in
            guard Self.exists(id: id, db: handle) else { throw DumpError.notFound }
            guard BucketRepository.fetchAll(db: handle, whereClause: "id = ?", bind: { sqlite3_bind_text($0, 1, (bucketId as NSString).utf8String, -1, SQLITE_TRANSIENT) }).first != nil else { throw DumpError.bucketNotFound }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sql = "UPDATE dumps SET bucket_id = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (bucketId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, nowMs); sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: sql) }
        }
    }

    func softDelete(id: String) throws {
        try db.withDB { handle in
            guard Self.exists(id: id, db: handle) else { throw DumpError.notFound }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "UPDATE dumps SET deleted_at = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: "softDelete") }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, nowMs); sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: "softDelete") }
        }
    }

    func restore(id: String) throws {
        try db.withDB { handle in
            guard Self.exists(id: id, db: handle) else { throw DumpError.notFound }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "UPDATE dumps SET deleted_at = NULL WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: "restore") }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)), sql: "restore") }
        }
    }

    func fetchFeed(bucketId: String?, searchQuery: String?, limit: Int?, offset: Int?) -> [Dump] {
        db.withDB { handle in Self.queryFeed(db: handle, bucketId: bucketId, searchQuery: searchQuery, limit: limit, offset: offset) }
    }
    func fetchGroupedFeed(bucketId: String?, searchQuery: String?) -> [DayGroup] {
        DayGroup.grouped(from: fetchFeed(bucketId: bucketId, searchQuery: searchQuery, limit: nil, offset: nil))
    }
    func search(query: String, bucketId: String?) -> [Dump] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return fetchFeed(bucketId: bucketId, searchQuery: t, limit: nil, offset: nil)
    }
    func countByBucket() -> [String: Int] {
        db.withDB { handle in
            var result: [String: Int] = [:]
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT bucket_id, COUNT(*) FROM dumps WHERE deleted_at IS NULL GROUP BY bucket_id;", -1, &stmt, nil) == SQLITE_OK else { return [:] }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { guard let c = sqlite3_column_text(stmt, 0) else { continue }; result[String(cString: c)] = Int(sqlite3_column_int64(stmt, 1)) }
            return result
        }
    }

    static func insert(dump: Dump, db: OpaquePointer) throws {
        let sql = "INSERT INTO dumps (id, bucket_id, content, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: sql) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (dump.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (dump.bucketId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, (dump.content as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, Int64(dump.createdAt.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 5, Int64(dump.updatedAt.timeIntervalSince1970 * 1000))
        if let d = dump.deletedAt { sqlite3_bind_int64(stmt, 6, Int64(d.timeIntervalSince1970 * 1000)) } else { sqlite3_bind_null(stmt, 6) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: sql) }
    }
    static func exists(id: String, db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM dumps WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int64(stmt, 0) > 0
    }
    static func queryFeed(db: OpaquePointer, bucketId: String?, searchQuery: String?, limit: Int?, offset: Int?) -> [Dump] {
        var sql = "SELECT id, bucket_id, content, created_at, updated_at, deleted_at FROM dumps WHERE deleted_at IS NULL"
        var bindings: [String] = []
        if let bid = bucketId { sql += " AND bucket_id = ?"; bindings.append(bid) }
        if let q = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty { sql += " AND content LIKE ? ESCAPE '\\' COLLATE NOCASE"; bindings.append("%\(escapeLike(q))%") }
        sql += " ORDER BY created_at DESC"
        if let lim = limit { sql += " LIMIT \(lim)"; if let off = offset { sql += " OFFSET \(off)" } } else if let off = offset { sql += " LIMIT -1 OFFSET \(off)" }
        sql += ";"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (idx, val) in bindings.enumerated() { sqlite3_bind_text(stmt, Int32(idx + 1), (val as NSString).utf8String, -1, SQLITE_TRANSIENT) }
        var dumps: [Dump] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let d = dumpFromRow(stmt!) { dumps.append(d) } }
        return dumps
    }
    static func dumpFromRow(_ stmt: OpaquePointer) -> Dump? {
        guard let idC = sqlite3_column_text(stmt, 0), let bucketIdC = sqlite3_column_text(stmt, 1), let contentC = sqlite3_column_text(stmt, 2) else { return nil }
        let createdAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 3)) / 1000.0)
        let updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 4)) / 1000.0)
        let deletedAt: Date? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 5)) / 1000.0) : nil
        return Dump(id: String(cString: idC), bucketId: String(cString: bucketIdC), content: String(cString: contentC), createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
    private static func escapeLike(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") }
}
