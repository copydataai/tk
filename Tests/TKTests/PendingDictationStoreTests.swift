import Foundation
import XCTest
@testable import TK

final class PendingDictationStoreTests: XCTestCase {
    func testAtomicallySavesAndRecoversOnePendingResult() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let pending = PendingDictation(
            operationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            text: "recover exactly this text",
            createdAt: Date(timeIntervalSince1970: 1_234),
            profileID: "dictation-profile",
            trust: .locallyRecognized,
            commitState: .ready
        )

        try fixture.store.save(pending)

        let reopened = PendingDictationStore(fileURL: fixture.fileURL)
        XCTAssertEqual(try reopened.load(), pending)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)[.posixPermissions] as? NSNumber,
            NSNumber(value: 0o600)
        )
    }

    func testSavingAnotherResultReplacesTheOnlyPendingResult() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = pending(text: "first")
        let second = pending(text: "second")

        try fixture.store.save(first)
        try fixture.store.save(second)

        XCTAssertEqual(try fixture.store.load(), second)
    }

    func testCorruptDataThrowsTypedRecoverableErrorAndPreservesFile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corruptData = Data("not json".utf8)
        try corruptData.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            guard case PendingDictationStoreError.corruptData = error else {
                return XCTFail("Expected corruptData, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), corruptData)
    }

    func testExplicitDiscardRemovesPendingResult() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.store.save(pending(text: "discard me"))

        try fixture.store.discard()

        XCTAssertNil(try fixture.store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testZeroHistoryRetentionDoesNotRemovePendingResult() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let history = try TranscriptStore(
            databaseURL: fixture.directory.appendingPathComponent("history.sqlite3"),
            retentionLimit: 0
        )
        try fixture.store.save(pending(text: "independent of history"))

        try history.insert("independent of history")
        try history.clear()

        XCTAssertEqual(try history.recent(), [])
        XCTAssertEqual(try fixture.store.load()?.text, "independent of history")
    }

    private func pending(text: String) -> PendingDictation {
        PendingDictation(
            operationID: UUID(),
            text: text,
            createdAt: Date(timeIntervalSince1970: 1),
            profileID: "profile",
            trust: .locallyRecognized,
            commitState: .ready
        )
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("pending-dictation.json")
        return Fixture(
            store: PendingDictationStore(fileURL: fileURL),
            directory: directory,
            fileURL: fileURL
        )
    }
}

private struct Fixture {
    let store: PendingDictationStore
    let directory: URL
    let fileURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
