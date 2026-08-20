import Foundation
import SQLite3

enum Migrations {

    static let currentVersion: Int32 = 1

    static func runMigrations(db: OpaquePointer) throws {
        let version = userVersion(db: db)
        if version < 1 {
            try migrateToV1(db: db)
            try setUserVersion(db: db, version: 1)
        }
        try bootstrapIfNeeded(db: db)
    }

    /// Ensures at least one active bucket exists. Idempotent. Creates an `Inbox`
    /// bucket if `SELECT COUNT(*) FROM buckets WHERE archived_at IS NULL` is 0,
    /// and sets `app_state.active_bucket_id` if missing.
    static func bootstrapIfNeeded(db: OpaquePointer) throws {
        // Count active buckets
        var countStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM buckets WHERE archived_at IS NULL;", -1, &countStmt, nil) == SQLITE_OK else {
            throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: "SELECT COUNT(*) FROM buckets WHERE archived_at IS NULL;")
        }
        defer { sqlite3_finalize(countStmt) }
        guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
        if sqlite3_column_int64(countStmt, 0) > 0 { return }

        // No active buckets — create Inbox
        let inboxId = UUID().uuidString
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let insertSQL = "INSERT INTO buckets (id, name, sort_order, created_at, updated_at, archived_at) VALUES (?, ?, ?, ?, ?, NULL);"
        var ins: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &ins, nil) == SQLITE_OK else {
            throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: insertSQL)
        }
        defer { sqlite3_finalize(ins) }
        let nsId = inboxId as NSString
        let nsName = "Inbox" as NSString
        sqlite3_bind_text(ins, 1, nsId.utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(ins, 2, nsName.utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(ins, 3, 0)
        sqlite3_bind_int64(ins, 4, nowMs)
        sqlite3_bind_int64(ins, 5, nowMs)
        guard sqlite3_step(ins) == SQLITE_DONE else {
            throw DatabaseError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)), sql: insertSQL)
        }

        // Set active_bucket_id in app_state if missing
        var check: OpaquePointer?
        var hasActive = false
        if sqlite3_prepare_v2(db, "SELECT value FROM app_state WHERE key = 'active_bucket_id';", -1, &check, nil) == SQLITE_OK {
            defer { sqlite3_finalize(check) }
            if sqlite3_step(check) == SQLITE_ROW, let cStr = sqlite3_column_text(check, 0) {
                let v = String(cString: cStr)
                hasActive = !v.isEmpty
            }
        }
        if !hasActive {
            let upsert = "INSERT INTO app_state (key, value) VALUES ('active_bucket_id', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
            var up: OpaquePointer?
            if sqlite3_prepare_v2(db, upsert, -1, &up, nil) == SQLITE_OK {
                defer { sqlite3_finalize(up) }
                sqlite3_bind_text(up, 1, nsId.utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_step(up)
            }
        }
    }

    static func userVersion(db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        return sqlite3_column_int(stmt, 0)
    }

    static func setUserVersion(db: OpaquePointer, version: Int32) throws {
        try exec(db: db, sql: "PRAGMA user_version = \(version);")
    }

    static func migrateToV1(db: OpaquePointer) throws {
        try exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS buckets (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                archived_at INTEGER
            );
            """)

        try exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS dumps (
                id TEXT PRIMARY KEY NOT NULL,
                bucket_id TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                FOREIGN KEY (bucket_id) REFERENCES buckets(id)
            );
            """)

        try exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT
            );
            """)

        try exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS capture_draft (
                singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
                bucket_id TEXT NOT NULL,
                content TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """)

        try exec(db: db, sql: "CREATE INDEX IF NOT EXISTS idx_dumps_created_at ON dumps(created_at);")
        try exec(db: db, sql: "CREATE INDEX IF NOT EXISTS idx_dumps_bucket_created ON dumps(bucket_id, created_at);")
        try exec(db: db, sql: "CREATE INDEX IF NOT EXISTS idx_dumps_deleted ON dumps(deleted_at);")
    }

    private static func exec(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg: String
            if let e = errMsg {
                msg = String(cString: e)
                sqlite3_free(e)
            } else {
                msg = String(cString: sqlite3_errmsg(db))
            }
            throw DatabaseError.sqliteError(code: rc, message: msg, sql: sql)
        }
    }
}
