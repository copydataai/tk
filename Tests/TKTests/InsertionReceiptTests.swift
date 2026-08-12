import XCTest
@testable import TK

final class InsertionReceiptTests: XCTestCase {
    func testMatchingAXReadbackIsVerified() {
        let verified = verifiedReceipt()
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(
                writeSucceeded: true,
                preStateReadable: true,
                postStateReadable: true,
                verifiedInsertion: verified
            ),
            .verified(verified)
        )
    }

    func testSuccessfulAXWriteWithUnreadablePrestateIsAttempted() {
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(
                writeSucceeded: true,
                preStateReadable: false,
                postStateReadable: true,
                verifiedInsertion: nil
            ),
            .attempted
        )
    }

    func testSuccessfulAXWriteWithUnreadablePoststateIsAttempted() {
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(
                writeSucceeded: true,
                preStateReadable: true,
                postStateReadable: false,
                verifiedInsertion: nil
            ),
            .attempted
        )
    }

    func testSuccessfulAXWriteWithReadableContradictoryPoststateFailsRecoverably() {
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(
                writeSucceeded: true,
                preStateReadable: true,
                postStateReadable: true,
                verifiedInsertion: nil
            ),
            .failedRecoverable(.readbackMismatch)
        )
    }

    func testChangedTargetFailsRecoverably() {
        let remembered = InsertionTargetFingerprint(
            processIdentifier: 41,
            bundleIdentifier: "com.example.Editor",
            role: "AXTextArea",
            subrole: nil,
            windowDigest: "window-a",
            elementIdentity: 7,
            readableStateDigest: "state-a"
        )
        let changed = InsertionTargetFingerprint(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Other",
            role: "AXTextArea",
            subrole: nil,
            windowDigest: "window-b",
            elementIdentity: 8,
            readableStateDigest: "state-b"
        )

        XCTAssertFalse(remembered.corresponds(to: changed))
        XCTAssertEqual(
            InsertionReceipt.targetMismatch,
            .failedRecoverable(.targetChanged)
        )
    }

    func testReceiptDiagnosticsContainOnlyBoundedReasonCodes() {
        XCTAssertEqual(
            InsertionReceipt.failedRecoverable(.unsupportedControl).diagnostic,
            "failedRecoverable:unsupportedControl"
        )
    }

    private func verifiedReceipt() -> VerifiedInsertion {
        VerifiedInsertion(
            operationID: UUID(),
            target: .init(
                processIdentifier: 1,
                bundleIdentifier: "test",
                role: "AXTextArea",
                subrole: nil,
                windowDigest: "window",
                elementIdentity: 1,
                readableStateDigest: InsertionTargetFingerprint.digest("text")
            ),
            insertedRange: NSRange(location: 0, length: 4),
            resultingSelectionRange: NSRange(location: 4, length: 0),
            resultingValue: "text",
            replacedText: "",
            surroundingStateDigest: InsertionTargetFingerprint.digest("")
        )
    }
}
