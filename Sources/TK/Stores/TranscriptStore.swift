import Foundation
import SQLite3

enum TranscriptContentTrust: String, Codable, Equatable, Sendable {
    case untrustedSpeechRecognition
}

enum TranscriptAgentEligibility: String, Codable, Equatable, Sendable {
    case ineligible
}

enum TranscriptRetentionDisposition: String, Codable, Equatable, Sendable {
    case retainedHistory
}

struct TranscriptRecord: Identifiable, Equatable {
    let id: Int64
    let text: String
    let createdAt: Date
    let contentTrust: TranscriptContentTrust
    let agentEligibility: TranscriptAgentEligibility
    let sourceOperationID: UUID?
    let retentionDisposition: TranscriptRetentionDisposition
}

struct DeletionArtifact: Equatable {
    enum Store: String, Equatable {
        case transcriptDatabase
        case writeAheadLog
        case sharedMemory
        case corruptArchive
        case pendingDictation
    }

    let store: Store
    let url: URL
}

struct DeletionResult: Equatable {
    let store: DeletionArtifact.Store
    let path: String
    let detail: String
}

struct DeletionReceipt: Equatable {
    let successes: [DeletionResult]
    let failures: [DeletionResult]
    let exclusions: [String]

    var summary: String {
        "Deleted or cleared \(successes.count) application-controlled stores; \(failures.count) failed."
    }
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

        try configureDeletionPolicy()
        try migrateSchema()
        try pruneToRetentionLimit()
    }

    deinit {
        sqlite3_close(database)
    }

    @discardableResult
    func insert(
        _ text: String,
        createdAt: Date = Date(),
        sourceOperationID: UUID? = nil
    ) throws -> TranscriptRecord {
        guard !text.isEmpty else {
            throw TranscriptStoreError.emptyText
        }

        let statement = try prepare(
            """
            INSERT INTO transcripts (
                text, created_at, content_trust, agent_eligibility,
                source_operation_id, retention_disposition
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, text, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_bind_double(statement, 2, createdAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_bind_text(statement, 3, TranscriptContentTrust.untrustedSpeechRecognition.rawValue, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_bind_text(statement, 4, TranscriptAgentEligibility.ineligible.rawValue, -1, sqliteTransient) == SQLITE_OK,
              bindOptionalText(sourceOperationID?.uuidString, to: statement, index: 5) == SQLITE_OK,
              sqlite3_bind_text(statement, 6, TranscriptRetentionDisposition.retainedHistory.rawValue, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError()
        }
        let record = TranscriptRecord(
            id: sqlite3_last_insert_rowid(database),
            text: text,
            createdAt: createdAt,
            contentTrust: .untrustedSpeechRecognition,
            agentEligibility: .ineligible,
            sourceOperationID: sourceOperationID,
            retentionDisposition: .retainedHistory
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
            SELECT id, text, created_at, content_trust, agent_eligibility,
                   source_operation_id, retention_disposition
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
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    contentTrust: TranscriptContentTrust(
                        rawValue: String(cString: sqlite3_column_text(statement, 3))
                    ) ?? .untrustedSpeechRecognition,
                    agentEligibility: TranscriptAgentEligibility(
                        rawValue: String(cString: sqlite3_column_text(statement, 4))
                    ) ?? .ineligible,
                    sourceOperationID: optionalString(statement, column: 5).flatMap(UUID.init(uuidString:)),
                    retentionDisposition: TranscriptRetentionDisposition(
                        rawValue: String(cString: sqlite3_column_text(statement, 6))
                    ) ?? .retainedHistory
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

    @discardableResult
    func clear(selectedArtifacts: [DeletionArtifact] = []) throws -> DeletionReceipt {
        var successes: [DeletionResult] = []
        var failures: [DeletionResult] = []
        try execute("DELETE FROM transcripts")
        successes.append(.init(
            store: .transcriptDatabase,
            path: databaseURL.path,
            detail: "Rows deleted with SQLite secure_delete=ON"
        ))

        do {
            try checkpointAndTruncateWAL()
            successes.append(.init(
                store: .writeAheadLog,
                path: databaseSidecars[0].url.path,
                detail: "Checkpointed and truncated while database remained open"
            ))
            successes.append(.init(
                store: .sharedMemory,
                path: databaseSidecars[1].url.path,
                detail: "SQLite shared-memory state coordinated by the open connection"
            ))
        } catch {
            failures.append(contentsOf: databaseSidecars.map {
                .init(store: $0.store, path: $0.url.path, detail: error.localizedDescription)
            })
        }
        for artifact in corruptArchiveArtifacts + selectedArtifacts {
            do {
                if FileManager.default.fileExists(atPath: artifact.url.path) {
                    try FileManager.default.removeItem(at: artifact.url)
                }
                successes.append(.init(store: artifact.store, path: artifact.url.path, detail: "Removed or absent"))
            } catch {
                failures.append(.init(store: artifact.store, path: artifact.url.path, detail: error.localizedDescription))
            }
        }
        return DeletionReceipt(
            successes: successes,
            failures: failures,
            exclusions: [
                "SSD controller, filesystem snapshots, backups, and free-space secure erasure are outside application control."
            ]
        )
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

    private func configureDeletionPolicy() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA secure_delete=ON")
    }

    private func migrateSchema() throws {
        let columns = try tableColumns()
        let additions = [
            ("content_trust", "TEXT NOT NULL DEFAULT 'untrustedSpeechRecognition'"),
            ("agent_eligibility", "TEXT NOT NULL DEFAULT 'ineligible'"),
            ("source_operation_id", "TEXT"),
            ("retention_disposition", "TEXT NOT NULL DEFAULT 'retainedHistory'"),
        ]
        for (name, declaration) in additions where !columns.contains(name) {
            try execute("ALTER TABLE transcripts ADD COLUMN \(name) \(declaration)")
        }
    }

    private func tableColumns() throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(transcripts)")
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            columns.insert(String(cString: sqlite3_column_text(statement, 1)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw sqliteError() }
        return columns
    }

    private func checkpointAndTruncateWAL() throws {
        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        guard sqlite3_wal_checkpoint_v2(
            database,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            &logFrames,
            &checkpointedFrames
        ) == SQLITE_OK else {
            throw sqliteError()
        }
    }

    private var databaseSidecars: [DeletionArtifact] {
        [
            .init(store: .writeAheadLog, url: URL(fileURLWithPath: databaseURL.path + "-wal")),
            .init(store: .sharedMemory, url: URL(fileURLWithPath: databaseURL.path + "-shm")),
        ]
    }

    private var corruptArchiveArtifacts: [DeletionArtifact] {
        let directory = databaseURL.deletingLastPathComponent()
        let prefix = databaseURL.lastPathComponent + ".corrupt-"
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return candidates.filter { $0.lastPathComponent.hasPrefix(prefix) }.map {
            .init(store: .corruptArchive, url: $0)
        }
    }

    private func bindOptionalText(_ text: String?, to statement: OpaquePointer, index: Int32) -> Int32 {
        guard let text else { return sqlite3_bind_null(statement, index) }
        return sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }

    private func optionalString(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
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
            created_at REAL NOT NULL,
            content_trust TEXT NOT NULL DEFAULT 'untrustedSpeechRecognition',
            agent_eligibility TEXT NOT NULL DEFAULT 'ineligible',
            source_operation_id TEXT,
            retention_disposition TEXT NOT NULL DEFAULT 'retainedHistory'
        )
        """
}

private struct ExportRecord: Encodable {
    let id: Int64
    let text: String
    let createdAt: Date
    let contentTrust: TranscriptContentTrust
    let agentEligibility: TranscriptAgentEligibility
    let sourceOperationID: UUID?
    let retentionDisposition: TranscriptRetentionDisposition

    init(_ record: TranscriptRecord) {
        id = record.id
        text = record.text
        createdAt = record.createdAt
        contentTrust = record.contentTrust
        agentEligibility = record.agentEligibility
        sourceOperationID = record.sourceOperationID
        retentionDisposition = record.retentionDisposition
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt = "created_at"
        case contentTrust
        case agentEligibility
        case sourceOperationID
        case retentionDisposition
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
