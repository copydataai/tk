import ApplicationServices
import XCTest
@testable import TK

final class CoreWorkflowTests: XCTestCase {
    @MainActor
    func testInsertionFailureAndRelaunchRecoverExactlyThePendingText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("pending-dictation.json")
        let store = PendingDictationStore(fileURL: fileURL)
        let operationID = UUID()
        let service = DictationService(pendingStore: store)
        service.acceptRecognizedCandidate(
            operationID: operationID,
            text: "words that must survive",
            profileID: "profile",
            createdAt: Date(timeIntervalSince1970: 42)
        )

        let receipt = try await service.commitCandidate(operationID: operationID) { _ in
            .failedRecoverable(.noFocusedControl)
        }

        XCTAssertEqual(receipt, .failedRecoverable(.noFocusedControl))
        let relaunched = DictationService(
            pendingStore: PendingDictationStore(fileURL: fileURL)
        )
        XCTAssertEqual(relaunched.pendingResult?.text, "words that must survive")
        XCTAssertEqual(relaunched.pendingResult?.commitState, .insertionFailed)
    }

    @MainActor
    func testSuccessfulDispositionAndExplicitDiscardRemovePendingArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingDictationStore(
            fileURL: directory.appendingPathComponent("pending-dictation.json")
        )
        let service = DictationService(pendingStore: store)
        let firstID = UUID()
        service.acceptRecognizedCandidate(
            operationID: firstID,
            text: "insert me",
            profileID: "profile"
        )

        let receipt = try await service.commitCandidate(operationID: firstID) { text in
            XCTAssertEqual(text, "insert me")
            XCTAssertEqual(try? store.load()?.commitState, .inserting)
            return self.verifiedReceipt(operationID: firstID, text: text)
        }
        XCTAssertEqual(receipt.operationID, firstID)
        XCTAssertNil(service.pendingResult)

        let secondID = UUID()
        service.acceptRecognizedCandidate(
            operationID: secondID,
            text: "discard me",
            profileID: "profile"
        )
        try service.persistCandidate(operationID: secondID)
        try service.discardPendingResult()
        XCTAssertNil(service.pendingResult)
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testEveryNonverifiedReceiptPreservesPendingText() async throws {
        let receipts: [InsertionReceipt] = [
            .attempted,
            .copyOnly,
            .failedRecoverable(.targetChanged)
        ]

        for expectedReceipt in receipts {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PendingDictationStore(
                fileURL: directory.appendingPathComponent("pending-dictation.json")
            )
            let service = DictationService(pendingStore: store)
            let operationID = UUID()
            service.acceptRecognizedCandidate(
                operationID: operationID,
                text: "keep until verified",
                profileID: "profile"
            )

            let receipt = try await service.commitCandidate(operationID: operationID) { _ in
                expectedReceipt
            }

            XCTAssertEqual(receipt, expectedReceipt)
            XCTAssertEqual(service.pendingResult?.text, "keep until verified")
            XCTAssertEqual(service.pendingResult?.commitState, .insertionFailed)
            XCTAssertEqual(try store.load()?.text, "keep until verified")
        }
    }

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

    func testOnboardingRequiresOnlyMicrophoneForCopyMode() {
        XCTAssertFalse(OnboardingReadiness(accessibilityGranted: false, microphoneGranted: false).canGetStarted)
        XCTAssertFalse(OnboardingReadiness(accessibilityGranted: true, microphoneGranted: false).canGetStarted)
        XCTAssertTrue(OnboardingReadiness(accessibilityGranted: false, microphoneGranted: true).canGetStarted)
        XCTAssertTrue(OnboardingReadiness(accessibilityGranted: true, microphoneGranted: true).canGetStarted)
    }

    func testCopyModeNeverAuthorizesAccessibilityWork() {
        let authority = DictationAuthority(accessibilityGranted: false)

        XCTAssertEqual(authority.mode, .copy)
        XCTAssertFalse(authority.mayCaptureInsertionTarget)
        XCTAssertFalse(authority.mayInsertAutomatically)
        XCTAssertTrue(authority.mayCopyToClipboard)
    }

    @MainActor
    func testCopyingAReadyResultReturnsCopyOnlyAndKeepsPendingText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingDictationStore(
            fileURL: directory.appendingPathComponent("pending-dictation.json")
        )
        let service = DictationService(pendingStore: store)
        let operationID = UUID()
        service.acceptRecognizedCandidate(
            operationID: operationID,
            text: "copy me",
            profileID: "profile"
        )

        let receipt = try service.copyPendingResult { text in
            XCTAssertEqual(text, "copy me")
        }

        XCTAssertEqual(receipt, .copyOnly)
        XCTAssertEqual(service.transaction?.state, .resultReady)
        XCTAssertEqual(service.pendingResult?.text, "copy me")
        XCTAssertEqual(try store.load()?.text, "copy me")
    }

    func testAccessibilityValueRejectsNonElementValues() {
        XCTAssertNil(MacAccessibility.element(from: "not an accessibility element" as CFTypeRef))
    }

    func testAccessibilityValueAcceptsARealSystemElement() {
        let systemElement = AXUIElementCreateSystemWide()

        XCTAssertNotNil(MacAccessibility.element(from: systemElement))
    }

    private func verifiedReceipt(operationID: UUID, text: String) -> InsertionReceipt {
        .verified(.init(
            operationID: operationID,
            target: .init(
                processIdentifier: 1,
                bundleIdentifier: "test",
                role: "AXTextArea",
                subrole: nil,
                windowDigest: "window",
                elementIdentity: 1,
                readableStateDigest: InsertionTargetFingerprint.digest(text)
            ),
            insertedRange: NSRange(location: 0, length: text.utf16.count),
            resultingSelectionRange: NSRange(location: text.utf16.count, length: 0),
            resultingValue: text,
            replacedText: "",
            surroundingStateDigest: InsertionTargetFingerprint.digest("")
        ))
    }
}
