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
        var transaction = DictationTransaction(profileID: "profile")
        var activity = DictationActivity(transaction: transaction)

        XCTAssertTrue(activity.isPreparing)

        try! transaction.transition(to: .cancelled)
        activity = DictationActivity(transaction: transaction)

        XCTAssertFalse(activity.isPreparing)
        XCTAssertFalse(activity.isRecording)
        XCTAssertFalse(activity.isTranscribing)
    }

    func testFinishingARecordingMovesThroughFinalizingAndTranscribing() {
        var transaction = DictationTransaction(profileID: "profile")
        try! transaction.transition(to: .recording)
        try! transaction.transition(to: .finalizing)
        var activity = DictationActivity(transaction: transaction)

        XCTAssertTrue(activity.isFinalizing)
        XCTAssertFalse(activity.isTranscribing)

        try! transaction.transition(to: .recognizing)
        activity = DictationActivity(transaction: transaction)
        XCTAssertFalse(activity.isFinalizing)
        XCTAssertTrue(activity.isTranscribing)

        try! transaction.setCandidateText("hello")
        activity = DictationActivity(transaction: transaction)
        XCTAssertFalse(activity.isTranscribing)
    }

    func testCancellingARecordingFinalizesWithoutTranscription() {
        var transaction = DictationTransaction(profileID: "profile")
        try! transaction.transition(to: .recording)
        try! transaction.transition(to: .finalizing)
        var activity = DictationActivity(transaction: transaction)

        XCTAssertTrue(activity.isFinalizing)
        XCTAssertFalse(activity.isTranscribing)

        try! transaction.transition(to: .cancelled)
        activity = DictationActivity(transaction: transaction)
        XCTAssertFalse(activity.isFinalizing)
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

    func testAccessibilityValueAcceptsARealSystemElement() {
        let systemElement = AXUIElementCreateSystemWide()

        XCTAssertNotNil(MacAccessibility.element(from: systemElement))
    }
}
