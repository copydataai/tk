import Foundation
import XCTest
@testable import TK

final class ResidentProcessRecordTests: XCTestCase {
    func testPersistsExecutableIdentityAndReadsLegacyWhisperPID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordURL = directory.appendingPathComponent("server.pid")
        let executableURL = URL(fileURLWithPath: "/tmp/tk moved/server")
        let record = ResidentProcessRecord(processIdentifier: 42, executableURL: executableURL)

        try record.write(to: recordURL)
        XCTAssertEqual(ResidentProcessRecord.read(from: recordURL), record)

        try Data("43\n".utf8).write(to: recordURL)
        XCTAssertEqual(
            ResidentProcessRecord.read(from: recordURL, legacyExecutableURL: executableURL),
            ResidentProcessRecord(processIdentifier: 43, executableURL: executableURL)
        )
    }
}
