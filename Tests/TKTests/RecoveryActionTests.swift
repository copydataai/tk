import XCTest
@testable import TK

final class RecoveryActionTests: XCTestCase {
    func testVerifiedInsertionAllowsTargetedUndoOnlyForExactCurrentState() {
        let operationID = UUID()
        let target = fingerprint(state: "post-state")
        let insertion = VerifiedInsertion(
            operationID: operationID,
            target: target,
            insertedRange: NSRange(location: 6, length: 5),
            resultingSelectionRange: NSRange(location: 11, length: 0),
            resultingValue: "hello world",
            replacedText: "",
            surroundingStateDigest: InsertionTargetFingerprint.digest("hello ")
        )
        let current = UndoTargetState(
            target: target,
            value: "hello world",
            selectedRange: NSRange(location: 11, length: 0)
        )

        XCTAssertEqual(insertion.undoRefusal(for: current), nil)
    }

    func testChangedTargetOrContentRefusesUndoWithExplanation() {
        let insertion = VerifiedInsertion(
            operationID: UUID(),
            target: fingerprint(state: "post-state"),
            insertedRange: NSRange(location: 6, length: 5),
            resultingSelectionRange: NSRange(location: 11, length: 0),
            resultingValue: "hello world",
            replacedText: "",
            surroundingStateDigest: InsertionTargetFingerprint.digest("hello ")
        )

        var changedTarget = fingerprint(state: "post-state")
        changedTarget = InsertionTargetFingerprint(
            processIdentifier: changedTarget.processIdentifier,
            bundleIdentifier: changedTarget.bundleIdentifier,
            role: changedTarget.role,
            subrole: changedTarget.subrole,
            windowDigest: changedTarget.windowDigest,
            elementIdentity: 99,
            readableStateDigest: changedTarget.readableStateDigest
        )
        XCTAssertEqual(
            insertion.undoRefusal(for: .init(
                target: changedTarget,
                value: "hello world",
                selectedRange: NSRange(location: 11, length: 0)
            )),
            "Undo is unavailable because the insertion target changed."
        )
        XCTAssertEqual(
            insertion.undoRefusal(for: .init(
                target: fingerprint(state: "changed"),
                value: "hello worlds",
                selectedRange: NSRange(location: 11, length: 0)
            )),
            "Undo is unavailable because the inserted text or surrounding content changed."
        )
    }

    @MainActor
    func testRetryCreatesNewVerifiedReceiptLinkedToSameOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = DictationService(pendingStore: PendingDictationStore(
            fileURL: directory.appendingPathComponent("pending.json")
        ))
        let operationID = UUID()
        service.acceptRecognizedCandidate(
            operationID: operationID,
            text: "retry me",
            profileID: "profile"
        )
        _ = try await service.commitCandidate(operationID: operationID) { _ in
            .failedRecoverable(.noFocusedControl)
        }
        let verified = verifiedReceipt(operationID: operationID, value: "retry me")

        let receipt = try await service.retryPendingResult { text, retriedOperationID in
            XCTAssertEqual(text, "retry me")
            XCTAssertEqual(retriedOperationID, operationID)
            return verified
        }

        XCTAssertEqual(receipt, verified)
        XCTAssertEqual(receipt.operationID, operationID)
        XCTAssertNil(service.pendingResult)
    }

    func testOnlyVerifiedReceiptOffersUndo() {
        XCTAssertNil(InsertionReceipt.attempted.verifiedInsertion)
        XCTAssertNil(InsertionReceipt.copyOnly.verifiedInsertion)
        XCTAssertNil(InsertionReceipt.failedRecoverable(.targetChanged).verifiedInsertion)
    }

    private func fingerprint(state: String) -> InsertionTargetFingerprint {
        InsertionTargetFingerprint(
            processIdentifier: 41,
            bundleIdentifier: "com.example.Editor",
            role: "AXTextArea",
            subrole: nil,
            windowDigest: "window-a",
            elementIdentity: 7,
            readableStateDigest: InsertionTargetFingerprint.digest(state)
        )
    }

    private func verifiedReceipt(operationID: UUID, value: String) -> InsertionReceipt {
        .verified(.init(
            operationID: operationID,
            target: fingerprint(state: value),
            insertedRange: NSRange(location: 0, length: value.utf16.count),
            resultingSelectionRange: NSRange(location: value.utf16.count, length: 0),
            resultingValue: value,
            replacedText: "",
            surroundingStateDigest: InsertionTargetFingerprint.digest("")
        ))
    }
}
