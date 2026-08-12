import XCTest
@testable import TK

final class OperationJournalTests: XCTestCase {
    func testTargetlessPendingTextRecoversWithoutPersistingContent() throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = UUID()
        try journal.append(.init(
            operationID: id,
            version: 1,
            predecessorVersion: nil,
            phase: .pendingResult,
            content: "private words",
            retention: .pendingText,
            reason: .completed
        ))

        let data = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(data.contains("private words"))
        XCTAssertEqual(try journal.recover()?.mayRetryInsertion, true)
        XCTAssertNil(try journal.recover()?.latest.destinationFingerprint)
    }

    func testRepeatedRecoveryCannotRetryVerifiedInsertion() throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = UUID()
        try journal.append(.init(operationID: id, version: 1, predecessorVersion: nil, phase: .insertionAttempt, content: "text", retention: .pendingText, reason: .started))
        try journal.append(.init(operationID: id, version: 2, predecessorVersion: 1, phase: .verification, content: "text", retention: .pendingText, reason: .completed, verifiedInsertion: true))

        XCTAssertEqual(try journal.recover()?.mayRetryInsertion, false)
        XCTAssertEqual(try journal.recover()?.mayRetryInsertion, false)
    }

    func testCorruptEvidenceIsPreservedAndFailsRecoverably() throws {
        let (journal, url) = makeJournal()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)

        XCTAssertThrowsError(try journal.recover()) { error in
            XCTAssertEqual(error as? OperationJournalError, .corruptEvidence)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testPredecessorMustFormAtomicVersionChain() throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertThrowsError(try journal.append(.init(operationID: UUID(), version: 2, predecessorVersion: 1, phase: .capture, retention: .temporaryAudio, reason: .started)))
    }

    private func makeJournal() -> (OperationJournal, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("operation.json")
        return (OperationJournal(fileURL: url), url)
    }
}
