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
