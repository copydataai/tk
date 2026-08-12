import AVFoundation
import XCTest
@testable import TK

final class MicrophoneCaptureTests: XCTestCase {
    func testSavedAndDefaultMicrophonesArePrioritized() {
        XCTAssertEqual(MicrophoneCapture.devicePriority("saved", savedID: "saved", defaultID: "default"), 0)
        XCTAssertEqual(MicrophoneCapture.devicePriority("default", savedID: "saved", defaultID: "default"), 1)
        XCTAssertEqual(MicrophoneCapture.devicePriority("other", savedID: "saved", defaultID: "default"), 2)
    }

    func testDigitalSilenceIsNotAWorkingInput() {
        XCTAssertTrue(MicrophoneCapture.isWorkingInput(level: -55))
        XCTAssertFalse(MicrophoneCapture.isWorkingInput(level: -758))
    }

    func testRecordingCompletionUsesAVFoundationSuccessFlag() {
        XCTAssertTrue(MicrophoneCapture.recordingSucceeded(nil))
        XCTAssertTrue(MicrophoneCapture.recordingSucceeded(NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.unknown.rawValue,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
        )))
        XCTAssertFalse(MicrophoneCapture.recordingSucceeded(NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.unknown.rawValue,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false]
        )))
    }

    func testProductionRecordingLimitsAreBounded() {
        XCTAssertEqual(MicrophoneCapture.Limits.production.maxDuration, 15 * 60)
        XCTAssertEqual(MicrophoneCapture.Limits.production.maxFileSize, 64 * 1024 * 1024)
    }

    func testRecordingLimitErrorsAreRejectedEvenWhenAVFoundationReportsSuccess() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.maximumDurationReached.rawValue,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
        )

        XCTAssertTrue(MicrophoneCapture.recordingLimitExceeded(error))
        XCTAssertFalse(MicrophoneCapture.recordingSucceeded(error))
    }
}
