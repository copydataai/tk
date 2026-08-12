import AppKit
import XCTest
@testable import TK

final class PasteboardSnapshotTests: XCTestCase {
    func testSuccessfulPasteEventIsAttemptedRatherThanVerified() {
        XCTAssertEqual(InsertionReceipt.pasteResult(eventPosted: true), .attempted)
    }

    func testUnavailablePasteEventLeavesRecoverableCopyOnlyReceipt() {
        XCTAssertEqual(InsertionReceipt.pasteResult(eventPosted: false), .copyOnly)
    }

    func testRestoresClipboardWhenTemporaryContentsAreStillOwned() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        let temporaryChangeCount = pasteboard.changeCount

        XCTAssertTrue(snapshot.restore(to: pasteboard, ifChangeCountIs: temporaryChangeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testDoesNotOverwriteClipboardChangedByAnotherOwner() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        let temporaryChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("new user copy", forType: .string)

        XCTAssertFalse(snapshot.restore(to: pasteboard, ifChangeCountIs: temporaryChangeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }
}
