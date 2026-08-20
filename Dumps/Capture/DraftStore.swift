import Foundation
import SQLite3

struct Draft: Equatable {
    let bucketId: String?
    let content: String
    let updatedAt: Date
    init(bucketId: String? = nil, content: String, updatedAt: Date = Date()) {
        if let b = bucketId, b.isEmpty { self.bucketId = nil } else { self.bucketId = bucketId }
        self.content = content
        self.updatedAt = updatedAt
    }
}

extension Optional where Wrapped == Draft {
    var content: String { switch self { case .some(let d): return d.content; case .none: return "" } }
    var bucketId: String? { switch self { case .some(let d): return d.bucketId; case .none: return nil } }
    var hasContent: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

final class DraftStore {
    static let shared = DraftStore()

    private let db: DatabaseManager
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var pendingTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.35

    init(db: DatabaseManager = DatabaseManager.shared) { self.db = db }

    var hasDraft: Bool {
        guard let d = load() else { return false }
        return !d.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var draftContent: String { load()?.content ?? "" }
    var draftBucketId: String? { load()?.bucketId }

    func save(content: String, bucketId: String?) {
        try? saveImmediately(bucketId: bucketId ?? "", content: content)
    }

    func save(bucketId: String, content: String) {
        try? saveImmediately(bucketId: bucketId, content: content)
    }

    func load() -> Draft? {
        var result: Draft?
        db.withDB { handle in
            let sql = "SELECT bucket_id, content, updated_at FROM capture_draft WHERE singleton_id = 1 LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return }
            let bucketId: String? = {
                guard let c = sqlite3_column_text(stmt, 0) else { return nil }
                let s = String(cString: c)
                return s.isEmpty ? nil : s
            }()
            let content: String = {
                guard let c = sqlite3_column_text(stmt, 1) else { return "" }
                return String(cString: c)
            }()
            let millis = sqlite3_column_int64(stmt, 2)
            let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
            result = Draft(bucketId: bucketId, content: content, updatedAt: date)
        }
        return result
    }

    func loadTuple() -> (content: String, bucketId: String?) {
        if let d = load() { return (d.content, d.bucketId) }
        return ("", nil)
    }

    func legacyLoad() -> (content: String, bucketId: String?) { loadTuple() }

    func saveImmediately(bucketId: String, content: String) throws {
        var opError: Error?
        db.withDB { handle in
            let sql = """
                INSERT INTO capture_draft (singleton_id, bucket_id, content, updated_at)
                VALUES (1, ?, ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET bucket_id=excluded.bucket_id, content=excluded.content, updated_at=excluded.updated_at;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                opError = DraftStoreError.sqlite(String(cString: sqlite3_errmsg(handle))); sqlite3_finalize(stmt); return
            }
            defer { sqlite3_finalize(stmt) }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            sqlite3_bind_text(stmt, 1, (bucketId as NSString).utf8String, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, nowMs)
            if sqlite3_step(stmt) != SQLITE_DONE {
                opError = DraftStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
        if let e = opError { throw e }
    }

    func scheduleSave(bucketId: String, content: String) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? self.saveImmediately(bucketId: bucketId, content: content)
        }
    }

    func cancelPendingSave() { pendingTask?.cancel(); pendingTask = nil }

    func clear() {
        pendingTask?.cancel(); pendingTask = nil
        db.withDB { handle in
            sqlite3_exec(handle, "DELETE FROM capture_draft WHERE singleton_id = 1;", nil, nil, nil)
        }
    }

    struct DraftTuple { let content: String; let bucketId: String? }
}

enum DraftStoreError: LocalizedError {
    case sqlite(String)
    var errorDescription: String? { switch self { case .sqlite(let m): return "SQLite error: \(m)" } }
}
