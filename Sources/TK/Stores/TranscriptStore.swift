import Foundation
import SQLite3

struct TranscriptRecord: Identifiable, Equatable {
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
    private let databaseURL: URL
    private let retentionLimit: Int

    static let defaultRetentionLimit = 50

    static func applicationSupport(
        retentionLimit: Int = TranscriptStore.defaultRetentionLimit
    ) throws -> TranscriptStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try TranscriptStore(
            databaseURL: directory
                .appendingPathComponent("tk", isDirectory: true)
                .appendingPathComponent("history.sqlite3"),
            retentionLimit: retentionLimit
        )
    }

    init(
        databaseURL: URL,
        retentionLimit: Int = TranscriptStore.defaultRetentionLimit
    ) throws {
        self.databaseURL = databaseURL
        self.retentionLimit = max(0, retentionLimit)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            database = try Self.openDatabase(at: databaseURL)
        } catch {
            guard Self.isCorruption(error) else { throw error }
            try Self.archiveCorruptDatabase(at: databaseURL)
            database = try Self.openDatabase(at: databaseURL)
        }

        try pruneToRetentionLimit()
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
        let record = TranscriptRecord(
            id: sqlite3_last_insert_rowid(database),
            text: text,
            createdAt: createdAt
        )
        try pruneToRetentionLimit()
        return record
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

    @discardableResult
    func delete(id: Int64) throws -> Bool {
        let statement = try prepare("DELETE FROM transcripts WHERE id = ?")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, id) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError()
        }
        return sqlite3_changes(database) > 0
    }

    func clear() throws {
        try execute("DELETE FROM transcripts")
        try Self.removeCorruptArchives(for: databaseURL)
    }

    @discardableResult
    func prune(keepingNewest limit: Int) throws -> Int {
        let limit = max(0, limit)
        let statement = try prepare(
            """
            DELETE FROM transcripts
            WHERE id NOT IN (
                SELECT id
                FROM transcripts
                ORDER BY created_at DESC, id DESC
                LIMIT ?
            )
            """
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, Int64(limit)) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError()
        }
        return Int(sqlite3_changes(database))
    }

    func exportData() throws -> Data {
        let records = try recent(limit: Int.max)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records.map(ExportRecord.init))
    }

    private func pruneToRetentionLimit() throws {
        try prune(keepingNewest: retentionLimit)
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

    private static func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let database { sqlite3_close(database) }
            throw TranscriptStoreError.sqlite(message)
        }

        let result = sqlite3_exec(database, createTableSQL, nil, nil, nil)
        guard result == SQLITE_OK else {
            let code = sqlite3_extended_errcode(database)
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            throw DatabaseOpenError(code: code, message: message)
        }
        return database
    }

    private static func isCorruption(_ error: Error) -> Bool {
        guard let error = error as? DatabaseOpenError else { return false }
        return error.code == SQLITE_CORRUPT || error.code == SQLITE_NOTADB
    }

    private static func archiveCorruptDatabase(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let archiveURL = url.appendingPathExtension("corrupt-\(UUID().uuidString)")
        try fileManager.moveItem(at: url, to: archiveURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.removeItem(at: sidecar)
            }
        }
    }

    private static func removeCorruptArchives(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".corrupt-"
        for candidate in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) where candidate.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: candidate)
        }
    }

    private static let createTableSQL =
        """
        CREATE TABLE IF NOT EXISTS transcripts (
            id INTEGER PRIMARY KEY,
            text TEXT NOT NULL CHECK(text <> ''),
            created_at REAL NOT NULL
        )
        """
}

private struct ExportRecord: Encodable {
    let id: Int64
    let text: String
    let createdAt: Date

    init(_ record: TranscriptRecord) {
        id = record.id
        text = record.text
        createdAt = record.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt = "created_at"
    }
}

private struct DatabaseOpenError: LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? {
        TranscriptStoreError.sqlite(message).errorDescription
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
