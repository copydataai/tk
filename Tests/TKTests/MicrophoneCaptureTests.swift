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
}
