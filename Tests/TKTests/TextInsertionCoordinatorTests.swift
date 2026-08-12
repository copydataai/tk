import Foundation
import XCTest
@testable import TK

final class TextInsertionCoordinatorTests: XCTestCase {
    func testPersistsBeforeDirectMutationAndVerifiesEmojiSafeReplacement() async throws {
        let target = snapshot(value: "A👨‍👩‍👧‍👦Z", range: NSRange(location: 1, length: 11))
        let adapter = FakeInsertionAdapter(states: [target, target], mutationSucceeds: true)
        adapter.postMutation = snapshot(value: "A🙂Z", range: NSRange(location: 3, length: 0))
        var persisted = false

        let result = try await TextInsertionCoordinator(adapter: adapter).insert(
            "🙂",
            operationID: UUID()
        ) {
            persisted = true
        }

        XCTAssertTrue(persisted)
        XCTAssertEqual(adapter.events, ["capture", "read", "replace", "read"])
        XCTAssertEqual(result.mutation, .directRange)
        XCTAssertTrue(result.receipt.isVerified)
    }

    func testChangedSelectionImmediatelyBeforeMutationIsRefused() async throws {
        let captured = snapshot(value: "hello", range: NSRange(location: 1, length: 0))
        let changed = snapshot(value: "hello", range: NSRange(location: 2, length: 0))
        let adapter = FakeInsertionAdapter(states: [captured, changed], mutationSucceeds: true)

        let result = try await TextInsertionCoordinator(adapter: adapter).insert("x", operationID: UUID()) {}

        XCTAssertEqual(result.receipt, .failedRecoverable(.targetChanged))
        XCTAssertEqual(adapter.events, ["capture", "read"])
    }

    func testSecureAndProtectedTargetsNeverMutate() async throws {
        for target in [
            snapshot(value: "", range: NSRange(location: 0, length: 0), secure: true),
            snapshot(value: "text", range: NSRange(location: 0, length: 0), editable: false)
        ] {
            let adapter = FakeInsertionAdapter(states: [target], mutationSucceeds: true)
            _ = try await TextInsertionCoordinator(adapter: adapter).insert("x", operationID: UUID()) {}
            XCTAssertEqual(adapter.events, ["capture"])
        }
    }

    func testFallbackIsSeparatelyClassifiedAndUnreadablePoststateIsNotVerified() async throws {
        let target = snapshot(
            value: "hello",
            range: NSRange(location: 5, length: 0),
            direct: false
        )
        let adapter = FakeInsertionAdapter(states: [target, target], mutationSucceeds: true)

        let result = try await TextInsertionCoordinator(adapter: adapter).insert("!", operationID: UUID()) {}

        XCTAssertEqual(result.mutation, .pasteboardFallback)
        XCTAssertEqual(result.receipt, .attempted)
        XCTAssertFalse(result.receipt.isVerified)
    }

    private func snapshot(
        value: String,
        range: NSRange,
        secure: Bool = false,
        editable: Bool = true,
        direct: Bool = true
    ) -> InsertionTargetSnapshot {
        .init(
            fingerprint: .init(
                processIdentifier: 1,
                bundleIdentifier: "test",
                role: "AXTextArea",
                subrole: secure ? "AXSecureTextField" : nil,
                windowDigest: "window",
                elementIdentity: 1,
                readableStateDigest: InsertionTargetFingerprint.digest(value)
            ),
            value: value,
            selectedRange: range,
            isSecure: secure,
            isEnabled: true,
            isEditable: editable,
            supportsDirectRangeMutation: direct
        )
    }
}

private final class FakeInsertionAdapter: TextInsertionAdapter, @unchecked Sendable {
    private var states: [InsertionTargetSnapshot]
    let mutationSucceeds: Bool
    var postMutation: InsertionTargetSnapshot?
    private(set) var events: [String] = []

    init(states: [InsertionTargetSnapshot], mutationSucceeds: Bool) {
        self.states = states
        self.mutationSucceeds = mutationSucceeds
    }

    func captureTarget() async -> InsertionTargetSnapshot? {
        events.append("capture")
        return states.isEmpty ? nil : states.removeFirst()
    }

    func replace(range: NSRange, with text: String, in target: InsertionTargetSnapshot) async -> Bool {
        events.append("replace")
        return mutationSucceeds
    }

    func paste(_ text: String, into target: InsertionTargetSnapshot) async -> Bool {
        events.append("paste")
        return mutationSucceeds
    }

    func readTarget() async -> InsertionTargetSnapshot? {
        events.append("read")
        if !states.isEmpty { return states.removeFirst() }
        defer { postMutation = nil }
        return postMutation
    }
}
