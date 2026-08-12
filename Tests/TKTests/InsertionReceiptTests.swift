import XCTest
@testable import TK

final class InsertionReceiptTests: XCTestCase {
    func testMatchingAXReadbackIsVerified() {
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(writeSucceeded: true, readbackMatches: true),
            .verified
        )
    }

    func testUnreadableAXPoststateIsOnlyAttempted() {
        XCTAssertEqual(
            InsertionReceipt.axWriteResult(writeSucceeded: true, readbackMatches: nil),
            .attempted
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
}
