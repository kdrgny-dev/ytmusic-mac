import Foundation
import SQLite3

/// SQLite declares this as a C macro, and macros don't survive the C import.
/// The -1 destructor tells SQLite to copy the bytes we bind instead of holding
/// a pointer into a Swift String that's already been deallocated by then.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue: Equatable {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    var intValue: Int64? { if case .int(let v) = self { return v } else { return nil } }
    var doubleValue: Double? { if case .double(let v) = self { return v } else { return nil } }
    var stringValue: String? { if case .text(let v) = self { return v } else { return nil } }
}

typealias SQLRow = [String: SQLValue]

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case exec(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite open: \(m)"
        case .prepare(let m): return "sqlite prepare: \(m)"
        case .step(let m): return "sqlite step: \(m)"
        case .exec(let m): return "sqlite exec: \(m)"
        }
    }
}

/// Minimal wrapper over the system libsqlite3 — no third-party dependency.
/// NOT thread-safe on its own; callers must serialize access (PlayHistoryStore
/// owns a serial queue for exactly this reason).
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Pass ":memory:" for a throwaway database (used by the tests).
    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK, handle != nil else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw SQLiteError.open(msg)
        }
        // WAL survives a hard kill mid-write and lets a future reader run
        // while playback is still appending rows.
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit { sqlite3_close(handle) }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    /// Multi-statement SQL with no parameters (schema setup, pragmas).
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.exec(errorMessage)
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(errorMessage)
        }
        return sqlite3_last_insert_rowid(handle)
    }

    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }

        var rows: [SQLRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw SQLiteError.step(errorMessage) }

            var row: SQLRow = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = columnValue(stmt, i)
            }
            rows.append(row)
        }
        return rows
    }

    /// Schema version, so a future migration knows what it's looking at.
    var userVersion: Int32 {
        get { (try? query("PRAGMA user_version;").first?["user_version"]?.intValue).flatMap { $0 }.map(Int32.init) ?? 0 }
        set { try? execute("PRAGMA user_version = \(newValue);") }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw SQLiteError.prepare(errorMessage)
        }
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch param {
            case .int(let v):    rc = sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):   rc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .null:          rc = sqlite3_bind_null(stmt, idx)
            }
            guard rc == SQLITE_OK else {
                sqlite3_finalize(stmt)
                throw SQLiteError.prepare(errorMessage)
            }
        }
        return stmt
    }

    private func columnValue(_ stmt: OpaquePointer?, _ i: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:   return .double(sqlite3_column_double(stmt, i))
        case SQLITE_TEXT:
            guard let cs = sqlite3_column_text(stmt, i) else { return .null }
            return .text(String(cString: cs))
        default: return .null
        }
    }
}
