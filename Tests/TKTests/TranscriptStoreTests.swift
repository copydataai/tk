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
}
