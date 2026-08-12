import Foundation
import XCTest
@testable import TK

final class DiagnosticsReportTests: XCTestCase {
    func testExportIsDeterministicAndContainsOnlySanitizedStatus() throws {
        let sensitiveStatus = "Failed transcript: secret words at /Users/alice/private/audio.wav"
        let report = DiagnosticsReport(
            appVersion: "1.2.3",
            macOSVersion: "14.6.1",
            architecture: "arm64",
            profileAvailability: [
                "reading.best-quality": .available,
                "dictation.balanced": .failed,
            ],
            accessibilityPermissionGranted: true,
            microphonePermissionGranted: false,
            status: DiagnosticsStatus(sanitizing: sensitiveStatus),
            performanceMeasurements: [:],
            performanceBudgetsPassed: [:]
        )

        let firstExport = try report.exportedData()
        let secondExport = try report.exportedData()
        XCTAssertEqual(firstExport, secondExport)
        XCTAssertEqual(
            String(decoding: firstExport, as: UTF8.self),
            """
            {
              "accessibilityPermissionGranted" : true,
              "appVersion" : "1.2.3",
              "architecture" : "arm64",
              "macOSVersion" : "14.6.1",
              "microphonePermissionGranted" : false,
              "performanceBudgetsPassed" : {

              },
              "performanceMeasurements" : {

              },
              "profileAvailability" : {
                "dictation.balanced" : "failed",
                "reading.best-quality" : "available"
              },
              "status" : "error"
            }

            """
        )

        let export = String(decoding: firstExport, as: UTF8.self)
        XCTAssertFalse(export.contains("secret words"))
        XCTAssertFalse(export.contains("/Users/"))
        XCTAssertFalse(export.contains("audio.wav"))
        XCTAssertFalse(export.lowercased().contains("transcript"))
    }

    func testProfileFailuresDiscardMessagesAndPaths() throws {
        let availability = DiagnosticsProfileAvailability(
            .failed("Could not read /Users/alice/models/private.bin")
        )
        XCTAssertEqual(availability, .failed)

        let encoded = try JSONEncoder().encode(availability)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"failed\"")
    }

    func testStatusSanitizerReturnsOnlyDeclaredCategories() {
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Ready"), .ready)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Recording /tmp/private.wav"), .recording)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Transcribing private words"), .transcribing)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Generating speech"), .reading)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Downloading profile"), .downloading)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Microphone permission required"), .unavailable)
        XCTAssertEqual(DiagnosticsStatus(sanitizing: "Unexpected private content"), .unknown)
    }
}
