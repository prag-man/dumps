import Foundation
import SQLite3

final class DatabaseManager {

    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dumps.database")
    private var isOpen = false

    var _inMemoryPath: String? = nil
    static var __test_lastDB: DatabaseManager? = nil

    private init() {}

    /// Test-only in-memory database. Uses a unique temp file that behaves like :memory: but supports WAL/migrations.
    static func __test_inMemory() -> DatabaseManager {
        let mgr = DatabaseManager()
        mgr._inMemoryPath = NSTemporaryDirectory() + "dumps_test_\(UUID().uuidString).sqlite"
        try? FileManager.default.createDirectory(atPath: (mgr._inMemoryPath! as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(mgr._inMemoryPath!, &handle, flags, nil)
        if rc == SQLITE_OK, let h = handle {
            mgr.db = h
            mgr.isOpen = true
            try? mgr.execOn(h, sql: "PRAGMA journal_mode=WAL;")
            try? mgr.execOn(h, sql: "PRAGMA foreign_keys=ON;")
            try? mgr.execOn(h, sql: "PRAGMA busy_timeout=5000;")
        }
        __test_lastDB = mgr
        return mgr
    }

    var databaseURL: URL {
        if let p = _inMemoryPath { return URL(fileURLWithPath: p) }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dumps", isDirectory: true).appendingPathComponent("dumps.sqlite")
    }

    deinit {
        close()
    }


    func open() throws {
        try queue.sync {
            try _open()
        }
    }

    private func _open() throws {
        if isOpen, db != nil { return }

        let directory = databaseURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let path = databaseURL.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let opened = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw DatabaseError.openFailed(msg)
        }
        db = opened
        isOpen = true

        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try exec("PRAGMA busy_timeout=5000;")
    }

    func close() {
        queue.sync {
            _close()
        }
    }

    private func _close() {
        if let handle = db {
            sqlite3_close(handle)
            db = nil
        }
        isOpen = false
    }

    var handle: OpaquePointer? {
        queue.sync { db }
    }

    func withDB<T>(_ block: (OpaquePointer) throws -> T) rethrows -> T {
        try queue.sync {
            if !isOpen || db == nil {
                try _open()
            }
            guard let handle = db else {
                fatalError("Database not open after _open()")
            }
            return try block(handle)
        }
    }

    func inTransaction(_ block: (OpaquePointer) throws -> Void) throws {
        try withDB { db in
            try execOn(db, sql: "BEGIN IMMEDIATE;")
            do {
                try block(db)
                try execOn(db, sql: "COMMIT;")
            } catch {
                try? execOn(db, sql: "ROLLBACK;")
                throw error
            }
        }
    }

    func exec(_ sql: String) throws {
        guard let handle = db else { throw DatabaseError.notOpen }
        try execOn(handle, sql: sql)
    }

    func execOn(_ db: OpaquePointer, sql: String) throws {
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

enum DatabaseError: Error, LocalizedError {
    case notOpen
    case openFailed(String)
    case sqliteError(code: Int32, message: String, sql: String)

    var errorDescription: String? {
        switch self {
        case .notOpen:
            return "Database is not open."
        case .openFailed(let msg):
            return "Failed to open database: \(msg)"
        case .sqliteError(let code, let msg, let sql):
            return "SQLite error \(code): \(msg) — SQL: \(sql)"
        }
    }
}
