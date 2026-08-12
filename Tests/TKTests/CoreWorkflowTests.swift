import ApplicationServices
import XCTest
@testable import TK

final class CoreWorkflowTests: XCTestCase {
    @MainActor
    func testDictationWithoutAnAvailableProfileExplainsHowToRecover() {
        let service = DictationService()

        service.toggle()

        XCTAssertEqual(service.status, "Choose an available dictation profile in Settings")
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isTranscribing)
    }

    func testCancellingPreparationReturnsDictationToIdle() {
        var activity = DictationActivity()
        activity.beginPreparing()

        XCTAssertTrue(activity.isPreparing)

        activity.cancelPreparation()

        XCTAssertFalse(activity.isPreparing)
        XCTAssertFalse(activity.isRecording)
        XCTAssertFalse(activity.isTranscribing)
    }

    func testFinishingARecordingMovesThroughFinalizingAndTranscribing() {
        var activity = DictationActivity()
        activity.beginPreparing()
        activity.beginRecording()
        activity.finishRecording(shouldTranscribe: true)

        XCTAssertTrue(activity.isFinalizing)
        XCTAssertTrue(activity.isTranscribing)

        XCTAssertTrue(activity.completeRecording())
        XCTAssertFalse(activity.isFinalizing)
        activity.completeTranscription()
        XCTAssertFalse(activity.isTranscribing)
    }

    @MainActor
    func testHotKeyRoutesEachRegisteredAction() {
        let service = GlobalHotKeyService()
        var actions: [String] = []
        service.onDictation = { actions.append("dictation") }
        service.onReadSelection = { actions.append("reading") }

        service.perform(id: 1)
        service.perform(id: 2)
        service.perform(id: 999)

        XCTAssertEqual(actions, ["dictation", "reading"])
    }

    func testOnboardingRequiresBothPermissions() {
        XCTAssertFalse(OnboardingReadiness(accessibilityGranted: false, microphoneGranted: false).canGetStarted)
        XCTAssertFalse(OnboardingReadiness(accessibilityGranted: true, microphoneGranted: false).canGetStarted)
        XCTAssertFalse(OnboardingReadiness(accessibilityGranted: false, microphoneGranted: true).canGetStarted)
        XCTAssertTrue(OnboardingReadiness(accessibilityGranted: true, microphoneGranted: true).canGetStarted)
    }

    func testAccessibilityValueRejectsNonElementValues() {
        XCTAssertNil(MacAccessibility.element(from: "not an accessibility element" as CFTypeRef))
    }
}
