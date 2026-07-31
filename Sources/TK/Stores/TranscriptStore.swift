import Foundation
import SQLite3

struct TranscriptRecord: Identifiable {
    let id: Int64
    let text: String
    let createdAt: Date
}

enum TranscriptStoreError: LocalizedError {
    case emptyText
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "Transcript text cannot be empty."
        case .sqlite(let message):
            "Transcript database error: \(message)"
        }
    }
}

final class TranscriptStore {
    private let database: OpaquePointer

    static func applicationSupport() throws -> TranscriptStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try TranscriptStore(
            databaseURL: directory
                .appendingPathComponent("tk", isDirectory: true)
                .appendingPathComponent("history.sqlite3")
        )
    }

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw TranscriptStoreError.sqlite(message)
        }
        self.database = database

        do {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS transcripts (
                    id INTEGER PRIMARY KEY,
                    text TEXT NOT NULL CHECK(text <> ''),
                    created_at REAL NOT NULL
                )
                """
            )
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    @discardableResult
    func insert(_ text: String, createdAt: Date = Date()) throws -> TranscriptRecord {
        guard !text.isEmpty else {
            throw TranscriptStoreError.emptyText
        }

        let statement = try prepare("INSERT INTO transcripts (text, created_at) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, text, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_bind_double(statement, 2, createdAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError()
        }
        return TranscriptRecord(
            id: sqlite3_last_insert_rowid(database),
            text: text,
            createdAt: createdAt
        )
    }

    func recent(limit: Int = 50) throws -> [TranscriptRecord] {
        guard limit > 0 else {
            return []
        }

        let statement = try prepare(
            """
            SELECT id, text, created_at
            FROM transcripts
            ORDER BY created_at DESC, id DESC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, Int64(limit)) == SQLITE_OK else {
            throw sqliteError()
        }

        var transcripts: [TranscriptRecord] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            transcripts.append(
                TranscriptRecord(
                    id: sqlite3_column_int64(statement, 0),
                    text: String(cString: sqlite3_column_text(statement, 1)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                )
            )
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw sqliteError()
        }
        return transcripts
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        return statement
    }

    private func sqliteError() -> TranscriptStoreError {
        .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
