import ApplicationServices
import XCTest
@testable import TK

final class CoreWorkflowTests: XCTestCase {
    @MainActor
    func testLiveTextServicePersistsBeforeTransactionalMutationAndUsesDirectRange() async throws {
        let target = productionSnapshot(value: "A👨‍👩‍👧‍👦Z", range: NSRange(location: 1, length: 11))
        let adapter = ProductionInsertionAdapter(states: [target, target])
        adapter.postMutation = productionSnapshot(value: "A🙂Z", range: NSRange(location: 3, length: 0))
        let service = MacTextService(insertionAdapter: adapter, accessibilityGranted: { true })
        var persisted = false

        let receipt = await service.insert("🙂", operationID: UUID()) {
            persisted = true
        }

        XCTAssertTrue(persisted)
        XCTAssertTrue(receipt.isVerified)
        XCTAssertEqual(adapter.events, ["capture", "read", "replace", "read"])
    }

    @MainActor
    func testLiveTextServiceRetainsCandidateWhenTargetChangesBeforeMutation() async throws {
        let captured = productionSnapshot(value: "hello", range: NSRange(location: 1, length: 0))
        let changed = productionSnapshot(value: "hello", range: NSRange(location: 2, length: 0))
        let adapter = ProductionInsertionAdapter(states: [captured, changed])
        let service = MacTextService(insertionAdapter: adapter, accessibilityGranted: { true })
        var persisted = false

        let receipt = await service.insert("x", operationID: UUID()) { persisted = true }

        XCTAssertTrue(persisted)
        XCTAssertEqual(receipt, .failedRecoverable(.targetChanged))
        XCTAssertEqual(adapter.events, ["capture", "read"])
    }

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
    func testProductionRelaunchRecoversJournaledTargetlessPendingOperationIdempotently() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pendingURL = directory.appendingPathComponent("pending.json")
        let journalURL = directory.appendingPathComponent("operation.json")
        let operationID = UUID()
        let first = DictationService(
            pendingStore: PendingDictationStore(fileURL: pendingURL),
            operationJournal: OperationJournal(fileURL: journalURL)
        )
        first.acceptRecognizedCandidate(operationID: operationID, text: "survive death", profileID: "profile")
        try first.persistCandidate(operationID: operationID)

        let relaunched = DictationService(
            pendingStore: PendingDictationStore(fileURL: pendingURL),
            operationJournal: OperationJournal(fileURL: journalURL)
        )
        let relaunchedAgain = DictationService(
            pendingStore: PendingDictationStore(fileURL: pendingURL),
            operationJournal: OperationJournal(fileURL: journalURL)
        )

        XCTAssertEqual(relaunched.pendingResult?.text, "survive death")
        XCTAssertEqual(relaunchedAgain.pendingResult?.operationID, operationID)
        XCTAssertTrue(try OperationJournal(fileURL: journalURL).recover()?.mayRetryInsertion == true)
    }

    @MainActor
    func testProductionRelaunchNeverRetriesAJournaledVerifiedInsertion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pendingURL = directory.appendingPathComponent("pending.json")
        let journalURL = directory.appendingPathComponent("operation.json")
        let operationID = UUID()
        let service = DictationService(
            pendingStore: PendingDictationStore(fileURL: pendingURL),
            operationJournal: OperationJournal(fileURL: journalURL)
        )
        service.acceptRecognizedCandidate(operationID: operationID, text: "insert once", profileID: "profile")
        _ = try await service.commitCandidate(operationID: operationID) { text in
            self.verifiedReceipt(operationID: operationID, text: text)
        }

        let relaunched = DictationService(
            pendingStore: PendingDictationStore(fileURL: pendingURL),
            operationJournal: OperationJournal(fileURL: journalURL)
        )

        XCTAssertNil(relaunched.pendingResult)
        XCTAssertFalse(try OperationJournal(fileURL: journalURL).recover()?.mayRetryInsertion ?? true)
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

    func testLiveSpeechDispatcherMakesZeroForbiddenCallsInCopyMode() async {
        let adapter = LiveCapabilityAdapter()
        var operationRan = false

        let authorized = await SpeechOperationDispatcher().dispatch(
            .copyModeDictation,
            using: adapter
        ) { operationRan = true }

        XCTAssertTrue(authorized)
        XCTAssertTrue(operationRan)
        XCTAssertEqual(adapter.requests, [.microphone])
        XCTAssertEqual(adapter.performances.filter {
            [.accessibility, .focusCapture, .selectedText, .syntheticEvents].contains($0)
        }.count, 0)
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

    @MainActor
    func testRecognitionInterruptionRemovesAudioAndReportsThatItWasNotRetained() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let operationID = UUID()
        let cleaner = OperationArtifactCleaner(rootURL: directory)
        let artifacts = try cleaner.createOperation(operationID: operationID)
        try Data("audio".utf8).write(to: artifacts.recordingURL)
        var transaction = DictationTransaction(operationID: operationID, profileID: "profile")
        try transaction.transition(to: .recording)
        try transaction.transition(to: .finalizing)
        transaction.setAudioState(.available(artifacts.recordingURL))
        try transaction.transition(to: .recognizing)
        let service = DictationService(
            artifactCleaner: cleaner,
            transaction: transaction
        )
        var reportedMessage: String?
        service.onContinuityNotification = { _, message in reportedMessage = message }

        service.handleContinuityEvent(.willSleep)

        XCTAssertEqual(
            reportedMessage,
            "Recognition was interrupted while this Mac slept. Audio was not retained."
        )
        XCTAssertEqual(service.transaction?.audioState, .discarded)
        XCTAssertNil(service.preservedAudioURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.directoryURL.path))
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

private func productionSnapshot(value: String, range: NSRange) -> InsertionTargetSnapshot {
    .init(
        fingerprint: .init(
            processIdentifier: 1,
            bundleIdentifier: "test",
            role: "AXTextArea",
            subrole: nil,
            windowDigest: "window",
            elementIdentity: 1,
            readableStateDigest: InsertionTargetFingerprint.digest(value)
        ),
        value: value,
        selectedRange: range,
        isSecure: false,
        isEnabled: true,
        isEditable: true,
        supportsDirectRangeMutation: true
    )
}

private final class ProductionInsertionAdapter: TextInsertionAdapter, @unchecked Sendable {
    private var states: [InsertionTargetSnapshot]
    var postMutation: InsertionTargetSnapshot?
    private(set) var events: [String] = []

    init(states: [InsertionTargetSnapshot]) { self.states = states }

    func captureTarget() async -> InsertionTargetSnapshot? {
        events.append("capture")
        return states.isEmpty ? nil : states.removeFirst()
    }

    func replace(range: NSRange, with text: String, in target: InsertionTargetSnapshot) async -> Bool {
        events.append("replace")
        return true
    }

    func paste(_ text: String, into target: InsertionTargetSnapshot) async -> Bool {
        events.append("paste")
        return true
    }

    func readTarget() async -> InsertionTargetSnapshot? {
        events.append("read")
        if !states.isEmpty { return states.removeFirst() }
        defer { postMutation = nil }
        return postMutation
    }
}

private final class LiveCapabilityAdapter: SpeechCapabilityAdapter {
    private(set) var requests: [SpeechCapability] = []
    private(set) var performances: [SpeechCapability] = []

    func request(_ capability: SpeechCapability) async -> Bool {
        requests.append(capability)
        return true
    }

    func perform(_ capability: SpeechCapability) async {
        performances.append(capability)
    }
}
