import Foundation
import SQLite3
import XCTest
@testable import TK

final class TranscriptTrustTests: XCTestCase {
    func testNewRecordsAreUntrustedAndAgentIneligible() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let operationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let record = try fixture.store.insert(
            "recognized speech",
            createdAt: Date(timeIntervalSince1970: 42),
            sourceOperationID: operationID
        )

        XCTAssertEqual(record.contentTrust, .untrustedSpeechRecognition)
        XCTAssertEqual(record.agentEligibility, .ineligible)
        XCTAssertEqual(record.sourceOperationID, operationID)
        XCTAssertEqual(record.retentionDisposition, .retainedHistory)

        let exports = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.store.exportData()) as? [[String: Any]]
        )
        let export = try XCTUnwrap(exports.first)
        XCTAssertEqual(export["contentTrust"] as? String, "untrustedSpeechRecognition")
        XCTAssertEqual(export["agentEligibility"] as? String, "ineligible")
        XCTAssertEqual(export["sourceOperationID"] as? String, operationID.uuidString)
        XCTAssertEqual(export["retentionDisposition"] as? String, "retainedHistory")
    }

    func testLegacyRowsMigrateToSafeTrustDefaults() throws {
        let fixture = try makeLegacyFixture()
        defer { fixture.cleanup() }

        let store = try TranscriptStore(databaseURL: fixture.databaseURL)
        let record = try XCTUnwrap(store.recent().first)

        XCTAssertEqual(record.text, "legacy speech")
        XCTAssertEqual(record.contentTrust, .untrustedSpeechRecognition)
        XCTAssertEqual(record.agentEligibility, .ineligible)
        XCTAssertNil(record.sourceOperationID)
        XCTAssertEqual(record.retentionDisposition, .retainedHistory)
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return Fixture(
            store: try TranscriptStore(databaseURL: directory.appendingPathComponent("history.sqlite3")),
            directory: directory,
            databaseURL: directory.appendingPathComponent("history.sqlite3")
        )
    }

    private func makeLegacyFixture() throws -> LegacyFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TABLE transcripts (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL CHECK(text <> ''),
                created_at REAL NOT NULL
            );
            INSERT INTO transcripts (text, created_at) VALUES ('legacy speech', 1);
            """, nil, nil, nil), SQLITE_OK)
        return LegacyFixture(directory: directory, databaseURL: databaseURL)
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

private struct LegacyFixture {
    let directory: URL
    let databaseURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
