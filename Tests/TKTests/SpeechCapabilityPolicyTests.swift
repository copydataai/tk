import XCTest
@testable import TK

final class SpeechCapabilityPolicyTests: XCTestCase {
    func testCopyModeMakesZeroForbiddenCapabilityCalls() async {
        let adapter = CapabilitySpy()
        XCTAssertTrue(await SpeechCapabilityPolicy().authorize(.copyModeDictation, using: adapter))
        XCTAssertEqual(adapter.requests, [.microphone])
        XCTAssertEqual(adapter.count(.accessibility), 0)
        XCTAssertEqual(adapter.count(.focusCapture), 0)
        XCTAssertEqual(adapter.count(.selectedText), 0)
        XCTAssertEqual(adapter.count(.syntheticEvents), 0)
    }

    func testAutomaticInsertionAndReadSelectionRequestOnlyOperationCapabilities() async {
        let insertion = CapabilitySpy()
        _ = await SpeechCapabilityPolicy().authorize(.automaticInsertion, using: insertion)
        XCTAssertEqual(Set(insertion.requests), [.microphone, .accessibility, .focusCapture])

        let reading = CapabilitySpy()
        _ = await SpeechCapabilityPolicy().authorize(.readSelection, using: reading)
        XCTAssertEqual(Set(reading.requests), [.accessibility, .focusCapture, .selectedText])
        XCTAssertEqual(reading.count(.microphone), 0)
    }

    func testClipboardRestoresOnlyWhileTemporaryValueIsStillOwned() {
        let temporary = "pending text"
        let token = ClipboardOwnershipToken(changeCount: 8, temporaryValueDigest: InsertionTargetFingerprint.digest(temporary))
        let policy = ClipboardRestorationPolicy()
        XCTAssertTrue(policy.mayRestore(token: token, currentChangeCount: 8, currentValue: temporary))
        XCTAssertFalse(policy.mayRestore(token: token, currentChangeCount: 9, currentValue: "another process"))
    }

    func testDeletionReceiptSanitizesPrivatePath() throws {
        let receipt = ContentFreeDeletionReceipt(storeCode: "pending", successCount: 1, failureCount: 0, path: URL(fileURLWithPath: "/Users/private/secret/pending.json"))
        let encoded = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
        XCTAssertFalse(encoded.contains("/Users/private"))
        XCTAssertEqual(receipt.sanitizedPathComponent, "pending.json")
    }
}

private final class CapabilitySpy: SpeechCapabilityAdapter {
    private(set) var requests: [SpeechCapability] = []
    func request(_ capability: SpeechCapability) async -> Bool { requests.append(capability); return true }
    func perform(_ capability: SpeechCapability) async {}
    func count(_ capability: SpeechCapability) -> Int { requests.filter { $0 == capability }.count }
}
