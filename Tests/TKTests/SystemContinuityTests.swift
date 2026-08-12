import Foundation
import XCTest
@testable import TK

final class SystemContinuityTests: XCTestCase {
    func testSleepDuringRecordingCancelsRecoverablyWithoutClaimingCompletion() {
        let decision = ContinuityPolicy.decision(
            for: .willSleep,
            transactionState: .recording,
            capturedDeviceID: "built-in"
        )

        XCTAssertEqual(decision, .interruptRecoverably(
            message: "Dictation stopped because this Mac went to sleep. No transcription was completed.",
            preserveAudio: false
        ))
    }

    func testCapturedMicrophoneDisconnectIsExplicitButAnotherDeviceDoesNotSwitchInput() {
        XCTAssertEqual(
            ContinuityPolicy.decision(
                for: .audioDeviceDisconnected(id: "usb"),
                transactionState: .recording,
                capturedDeviceID: "usb"
            ),
            .interruptRecoverably(
                message: "The recording microphone disconnected. Dictation stopped without switching microphones.",
                preserveAudio: false
            )
        )
        XCTAssertEqual(
            ContinuityPolicy.decision(
                for: .audioDeviceConnected(id: "bluetooth"),
                transactionState: .recording,
                capturedDeviceID: "usb"
            ),
            .continueCurrentOperation
        )
    }

    func testWakeInvalidatesStaleWorkAndRequiresADeviceReprobeForANewTransaction() {
        XCTAssertEqual(
            ContinuityPolicy.decision(
                for: .didWake,
                transactionState: .recognizing,
                capturedDeviceID: "usb"
            ),
            .interruptRecoverably(
                message: "Dictation was interrupted while this Mac slept. Audio was preserved for recovery.",
                preserveAudio: true
            )
        )
        XCTAssertTrue(ContinuityPolicy.requiresDeviceReprobe(after: .didWake))
    }

    func testResourcePressureDegradesAtWarningAndBlocksAtCriticalWithoutChangingProfile() {
        XCTAssertEqual(
            ContinuityPolicy.decision(
                for: .resourcePressure(.degraded),
                transactionState: .recognizing,
                capturedDeviceID: nil
            ),
            .continueDegraded(message: "System resources are constrained. Current recognition will continue without changing profiles.")
        )
        XCTAssertEqual(
            ContinuityPolicy.decision(
                for: .resourcePressure(.blocked),
                transactionState: .recognizing,
                capturedDeviceID: nil
            ),
            .resourceBlocked(
                message: "Recognition stopped because system resources are critically constrained. Audio was preserved for recovery.",
                preserveAudio: true
            )
        )
    }

    func testAcceptanceNotificationMappingIsStableAndTruthful() {
        XCTAssertEqual(
            ContinuityNotification.interruptedRecoverable.title,
            "Dictation interrupted"
        )
        XCTAssertEqual(ContinuityNotification.degraded.title, "Dictation degraded")
        XCTAssertEqual(ContinuityNotification.resourceBlocked.title, "Dictation blocked")
    }
}
