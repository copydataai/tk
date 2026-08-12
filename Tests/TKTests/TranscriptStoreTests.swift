import Foundation
import XCTest
@testable import TK

final class TranscriptStoreTests: XCTestCase {
    func testReopensDatabaseAndReturnsNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("transcripts.sqlite")

        do {
            let store = try TranscriptStore(databaseURL: databaseURL)
            try store.insert("older", createdAt: Date(timeIntervalSince1970: 1))
            try store.insert("newer", createdAt: Date(timeIntervalSince1970: 2))
        }

        let reopenedStore = try TranscriptStore(databaseURL: databaseURL)
        let records = try reopenedStore.recent()
        XCTAssertEqual(records.map(\.text), ["newer", "older"])
        XCTAssertEqual(
            records.map(\.createdAt),
            [Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 1)]
        )
        XCTAssertEqual(try reopenedStore.recent(limit: 1).map(\.text), ["newer"])
        XCTAssertThrowsError(try reopenedStore.insert(""))
    }

    func testDeletesOneTranscriptAndClearsAll() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let first = try fixture.store.insert("first")
        let second = try fixture.store.insert("second")

        XCTAssertTrue(try fixture.store.delete(id: first.id))
        XCTAssertFalse(try fixture.store.delete(id: first.id))
        let remaining = try fixture.store.recent()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertEqual(remaining.map(\.text), [second.text])

        try fixture.store.clear()
        XCTAssertEqual(try fixture.store.recent(), [])
    }

    func testAutomaticallyPrunesToRetentionLimit() throws {
        let fixture = try makeFixture(retentionLimit: 2)
        defer { fixture.cleanup() }

        try fixture.store.insert("oldest", createdAt: Date(timeIntervalSince1970: 1))
        try fixture.store.insert("newest", createdAt: Date(timeIntervalSince1970: 3))
        try fixture.store.insert("middle", createdAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(try fixture.store.recent().map(\.text), ["newest", "middle"])
    }

    func testZeroRetentionDoesNotKeepInsertedTranscripts() throws {
        let fixture = try makeFixture(retentionLimit: 0)
        defer { fixture.cleanup() }

        try fixture.store.insert("private words")

        XCTAssertEqual(try fixture.store.recent(), [])
    }

    func testPrunesExistingDatabaseWhenOpenedWithLowerRetentionLimit() throws {
        let fixture = try makeFixture(retentionLimit: 10)
        defer { fixture.cleanup() }
        try fixture.store.insert("old", createdAt: Date(timeIntervalSince1970: 1))
        try fixture.store.insert("new", createdAt: Date(timeIntervalSince1970: 2))

        let reopened = try TranscriptStore(databaseURL: fixture.databaseURL, retentionLimit: 1)

        XCTAssertEqual(try reopened.recent().map(\.text), ["new"])
    }

    func testGeneratesJSONExportNewestFirst() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.store.insert("older", createdAt: Date(timeIntervalSince1970: 1))
        try fixture.store.insert("newer", createdAt: Date(timeIntervalSince1970: 2))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.store.exportData()) as? [[String: Any]]
        )

        XCTAssertEqual(object.compactMap { $0["text"] as? String }, ["newer", "older"])
        XCTAssertNotNil(object.first?["id"])
        XCTAssertNotNil(object.first?["created_at"])
    }

    func testArchivesCorruptDatabaseAndStartsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("transcripts.sqlite")
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        let store = try TranscriptStore(databaseURL: databaseURL)

        XCTAssertEqual(try store.recent(), [])
        let archivedFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("transcripts.sqlite.corrupt-") }
        XCTAssertEqual(archivedFiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: archivedFiles[0]), Data("not a sqlite database".utf8))

        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivedFiles[0].path))
    }

    private func makeFixture(
        retentionLimit: Int = TranscriptStore.defaultRetentionLimit
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("transcripts.sqlite")
        return Fixture(
            store: try TranscriptStore(
                databaseURL: databaseURL,
                retentionLimit: retentionLimit
            ),
            directory: directory,
            databaseURL: databaseURL
        )
    }
}

private struct Fixture {
    let store: TranscriptStore
    let directory: URL
    let databaseURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
