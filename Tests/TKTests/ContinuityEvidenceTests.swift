import XCTest
@testable import TK

final class ContinuityEvidenceTests: XCTestCase {
    func testSimulatedPassCannotQualifyPhysicalRow() {
        let record = makeRecord(kind: .simulated, outcome: .pass)
        XCTAssertThrowsError(try ContinuityEvidenceValidator().validate(record, rows: [row])) {
            XCTAssertEqual($0 as? ContinuityEvidenceError, .simulatedCannotPass)
        }
        XCTAssertEqual(ContinuityEvidenceAggregator().statuses(rows: [row], records: [record])[row.id], .notRun)
    }

    func testOneFreshPhysicalRecordMapsToExactlyOneRow() throws {
        let record = makeRecord(kind: .physical, outcome: .pass)
        XCTAssertEqual(try ContinuityEvidenceValidator().validate(record, rows: [row]).id, row.id)
        XCTAssertEqual(ContinuityEvidenceAggregator().statuses(rows: [row], records: [record])[row.id], .pass)
    }

    func testStaleDeviceAndMissingObservationsAreRejected() {
        let stale = makeRecord(kind: .physical, outcome: .fail, deviceUID: "other")
        XCTAssertThrowsError(try ContinuityEvidenceValidator().validate(stale, rows: [row])) {
            XCTAssertEqual($0 as? ContinuityEvidenceError, .staleDevice)
        }
    }

    private var row: ContinuityMatrixRow {
        .init(id: "mic-usb-recording-disconnect", expectedAppVersion: "1.0", expectedArtifactSHA256: "abc", expectedMacOSBuild: "24A", expectedHardwareIdentifier: "Mac15,6", expectedInputDeviceUID: "usb-1")
    }

    private func makeRecord(kind: EvidenceKind, outcome: QualificationStatus, deviceUID: String = "usb-1") -> ContinuityEvidenceRecord {
        .init(schemaVersion: 1, rowID: row.id, kind: kind, appVersion: "1.0", artifactSHA256: "abc", macOSBuild: "24A", hardwareIdentifier: "Mac15,6", inputRoute: "USB", inputDeviceUID: deviceUID, sampleRate: 48_000, operationID: UUID(), interruptionPhase: "recording", notificationsObserved: ["deviceDisconnected"], outcome: outcome, audioDisposition: "removed", helperDisposition: "notStarted", testerAssertion: "Observed physical disconnect and recovery", recordedAt: Date())
    }
}
