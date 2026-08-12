import CryptoKit
import Foundation

enum OperationPhase: String, Codable, CaseIterable, Sendable {
    case capture, inference, pendingResult, destinationChoice, insertionAttempt
    case verification, retry, copy, discard, commit
}

enum RetentionDisposition: String, Codable, Sendable {
    case temporaryAudio, pendingText, retainedHistory, clipboardExposed, discarded
}

enum OperationReasonCode: String, Codable, Sendable {
    case started, completed, interrupted, refused, unavailable, mismatch, userRequested, corrupt
}

struct OperationJournalEntry: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let version: Int
    let predecessorVersion: Int?
    let phase: OperationPhase
    let contentDigest: String?
    let retention: RetentionDisposition
    let destinationFingerprint: InsertionTargetFingerprintRecord?
    let reason: OperationReasonCode
    let timestamp: Date
    let verifiedInsertion: Bool

    init(
        operationID: UUID,
        version: Int,
        predecessorVersion: Int?,
        phase: OperationPhase,
        content: String? = nil,
        retention: RetentionDisposition,
        destinationFingerprint: InsertionTargetFingerprint? = nil,
        reason: OperationReasonCode,
        timestamp: Date = Date(),
        verifiedInsertion: Bool = false
    ) {
        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.version = version
        self.predecessorVersion = predecessorVersion
        self.phase = phase
        contentDigest = content.map(Self.digest)
        self.retention = retention
        self.destinationFingerprint = destinationFingerprint.map(InsertionTargetFingerprintRecord.init)
        self.reason = reason
        self.timestamp = timestamp
        self.verifiedInsertion = verifiedInsertion
    }

    static func digest(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct InsertionTargetFingerprintRecord: Codable, Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let role: String?
    let subrole: String?
    let windowDigest: String?
    let elementIdentity: UInt
    let readableStateDigest: String?

    init(_ value: InsertionTargetFingerprint) {
        processIdentifier = value.processIdentifier
        bundleIdentifier = value.bundleIdentifier
        role = value.role
        subrole = value.subrole
        windowDigest = value.windowDigest
        elementIdentity = value.elementIdentity
        readableStateDigest = value.readableStateDigest
    }
}

enum OperationJournalError: Error, Equatable {
    case corruptEvidence
    case futureSchema(Int)
    case invalidPredecessor(expected: Int?, actual: Int?)
    case operationMismatch
}

struct OperationRecovery: Equatable, Sendable {
    let latest: OperationJournalEntry
    let mayRetryInsertion: Bool
    let isComplete: Bool
}

final class OperationJournal {
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    static func applicationSupport() throws -> OperationJournal {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return OperationJournal(fileURL: directory
            .appendingPathComponent("tk", isDirectory: true)
            .appendingPathComponent("operation-journal.json"))
    }

    func append(_ entry: OperationJournalEntry) throws {
        var entries = try loadIfPresent()
        if let latest = entries.last, latest.operationID == entry.operationID {
            guard entry.predecessorVersion == latest.version else {
                throw OperationJournalError.invalidPredecessor(
                    expected: latest.version,
                    actual: entry.predecessorVersion
                )
            }
            if latest == entry { return }
        } else if let latest = entries.last {
            let complete = latest.phase == .commit || latest.phase == .discard || latest.verifiedInsertion
            guard complete else { throw OperationJournalError.operationMismatch }
            guard entry.predecessorVersion == nil, entry.version == 1 else {
                throw OperationJournalError.invalidPredecessor(expected: nil, actual: entry.predecessorVersion)
            }
        } else if entry.predecessorVersion != nil {
            throw OperationJournalError.invalidPredecessor(expected: nil, actual: entry.predecessorVersion)
        }
        entries.append(entry)
        try persist(entries)
    }

    func recover() throws -> OperationRecovery? {
        guard let latest = try loadIfPresent().last else { return nil }
        let complete = latest.phase == .commit || latest.phase == .discard || latest.verifiedInsertion
        return OperationRecovery(
            latest: latest,
            mayRetryInsertion: !complete && latest.contentDigest != nil,
            isComplete: complete
        )
    }

    func entries() throws -> [OperationJournalEntry] { try loadIfPresent() }

    private func loadIfPresent() throws -> [OperationJournalEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let entries = try Self.decoder.decode([OperationJournalEntry].self, from: Data(contentsOf: fileURL))
            guard entries.allSatisfy({ $0.schemaVersion <= OperationJournalEntry.schemaVersion }) else {
                throw OperationJournalError.futureSchema(entries.map(\.schemaVersion).max() ?? 0)
            }
            for (index, entry) in entries.enumerated() {
                let predecessor = index == 0 || entries[index - 1].operationID != entry.operationID
                    ? nil
                    : entries[index - 1].version
                guard entry.predecessorVersion == predecessor else {
                    throw OperationJournalError.invalidPredecessor(
                        expected: predecessor,
                        actual: entry.predecessorVersion
                    )
                }
            }
            return entries
        } catch let error as OperationJournalError {
            throw error
        } catch {
            throw OperationJournalError.corruptEvidence
        }
    }

    private func persist(_ entries: [OperationJournalEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Self.encoder.encode(entries).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .millisecondsSince1970
        value.outputFormatting = [.sortedKeys]
        return value
    }()
    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }()
}
