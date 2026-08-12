import Foundation

struct InsertionTargetSnapshot: Equatable, Sendable {
    let fingerprint: InsertionTargetFingerprint
    let value: String
    let selectedRange: NSRange
    let isSecure: Bool
    let isEnabled: Bool
    let isEditable: Bool
    let supportsDirectRangeMutation: Bool
}

enum TextInsertionMutation: Equatable, Sendable {
    case directRange
    case pasteboardFallback
}

protocol TextInsertionAdapter: Sendable {
    func captureTarget() async -> InsertionTargetSnapshot?
    func replace(range: NSRange, with text: String, in target: InsertionTargetSnapshot) async -> Bool
    func paste(_ text: String, into target: InsertionTargetSnapshot) async -> Bool
    func readTarget() async -> InsertionTargetSnapshot?
}

struct TextInsertionCoordinator: Sendable {
    struct Result: Equatable, Sendable {
        let receipt: InsertionReceipt
        let mutation: TextInsertionMutation?
    }

    private let adapter: any TextInsertionAdapter

    init(adapter: any TextInsertionAdapter) {
        self.adapter = adapter
    }

    func insert(
        _ text: String,
        operationID: UUID,
        persistCandidate: () async throws -> Void
    ) async throws -> Result {
        try await persistCandidate()
        guard !text.isEmpty else {
            return Result(receipt: .failedRecoverable(.readbackMismatch), mutation: nil)
        }
        guard let captured = await adapter.captureTarget() else {
            return Result(receipt: .failedRecoverable(.noFocusedControl), mutation: nil)
        }
        guard !captured.isSecure else {
            return Result(receipt: .failedRecoverable(.secureField), mutation: nil)
        }
        guard captured.isEnabled, captured.isEditable else {
            return Result(receipt: .failedRecoverable(.protectedControl), mutation: nil)
        }
        guard Self.isValid(captured.selectedRange, in: captured.value) else {
            return Result(receipt: .failedRecoverable(.ambiguousTarget), mutation: nil)
        }
        guard let immediate = await adapter.readTarget(), immediate == captured else {
            return Result(receipt: .failedRecoverable(.targetChanged), mutation: nil)
        }

        let mutation: TextInsertionMutation
        let mutated: Bool
        if captured.supportsDirectRangeMutation {
            mutation = .directRange
            mutated = await adapter.replace(range: captured.selectedRange, with: text, in: captured)
        } else {
            mutation = .pasteboardFallback
            mutated = await adapter.paste(text, into: captured)
        }
        guard mutated else {
            return Result(receipt: .failedRecoverable(.unsupportedControl), mutation: mutation)
        }
        guard let post = await adapter.readTarget() else {
            return Result(receipt: .attempted, mutation: mutation)
        }
        guard captured.fingerprint.sameTarget(as: post.fingerprint) else {
            return Result(receipt: .failedRecoverable(.targetChanged), mutation: mutation)
        }
        let expected = (captured.value as NSString).replacingCharacters(in: captured.selectedRange, with: text)
        let insertedRange = NSRange(
            location: captured.selectedRange.location,
            length: (text as NSString).length
        )
        guard post.value == expected,
              post.selectedRange.location == NSMaxRange(insertedRange),
              post.selectedRange.length == 0 else {
            return Result(receipt: .failedRecoverable(.readbackMismatch), mutation: mutation)
        }
        let surrounding = (post.value as NSString).replacingCharacters(in: insertedRange, with: "")
        let replaced = (captured.value as NSString).substring(with: captured.selectedRange)
        return Result(
            receipt: .verified(.init(
                operationID: operationID,
                target: post.fingerprint,
                insertedRange: insertedRange,
                resultingSelectionRange: post.selectedRange,
                resultingValue: post.value,
                replacedText: replaced,
                surroundingStateDigest: InsertionTargetFingerprint.digest(surrounding)
            )),
            mutation: mutation
        )
    }

    private static func isValid(_ range: NSRange, in value: String) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= (value as NSString).length,
              let swiftRange = Range(range, in: value) else { return false }
        return swiftRange.lowerBound == value.index(value.startIndex, offsetBy: value.distance(from: value.startIndex, to: swiftRange.lowerBound))
    }
}
