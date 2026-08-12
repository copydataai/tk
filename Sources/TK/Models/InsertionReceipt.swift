import CryptoKit
import Foundation

enum InsertionFailureReason: String, Equatable, Sendable {
    case accessibilityRequired
    case noFocusedControl
    case targetChanged
    case unsupportedControl
    case readbackMismatch
}

struct UndoTargetState: Equatable, Sendable {
    let target: InsertionTargetFingerprint
    let value: String
    let selectedRange: NSRange
}

struct VerifiedInsertion: Equatable, Sendable {
    let operationID: UUID
    let target: InsertionTargetFingerprint
    let insertedRange: NSRange
    let resultingSelectionRange: NSRange
    let resultingValue: String
    let replacedText: String
    let surroundingStateDigest: String

    func undoRefusal(for current: UndoTargetState) -> String? {
        guard target.sameTarget(as: current.target) else {
            return "Undo is unavailable because the insertion target changed."
        }
        guard current.value == resultingValue,
              current.selectedRange == resultingSelectionRange,
              surroundingDigest(in: current.value) == surroundingStateDigest else {
            return "Undo is unavailable because the inserted text or surrounding content changed."
        }
        return nil
    }

    private func surroundingDigest(in value: String) -> String? {
        guard let range = Range(insertedRange, in: value) else { return nil }
        return InsertionTargetFingerprint.digest(String(value[..<range.lowerBound] + value[range.upperBound...]))
    }
}

enum InsertionReceipt: Equatable, Sendable {
    case verified(VerifiedInsertion)
    case attempted
    case copyOnly
    case failedRecoverable(InsertionFailureReason)

    static let targetMismatch = Self.failedRecoverable(.targetChanged)

    static func axWriteResult(writeSucceeded: Bool, verifiedInsertion: VerifiedInsertion?) -> Self {
        guard writeSucceeded else { return .failedRecoverable(.unsupportedControl) }
        return verifiedInsertion.map(Self.verified) ?? .failedRecoverable(.readbackMismatch)
    }

    static func pasteResult(eventPosted: Bool) -> Self {
        eventPosted ? .attempted : .copyOnly
    }

    var verifiedInsertion: VerifiedInsertion? {
        guard case .verified(let insertion) = self else { return nil }
        return insertion
    }

    var operationID: UUID? { verifiedInsertion?.operationID }
    var isVerified: Bool { verifiedInsertion != nil }

    var diagnostic: String {
        switch self {
        case .verified:
            "verified"
        case .attempted:
            "attempted"
        case .copyOnly:
            "copyOnly"
        case .failedRecoverable(let reason):
            "failedRecoverable:\(reason.rawValue)"
        }
    }
}

struct InsertionTargetFingerprint: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let role: String?
    let subrole: String?
    let windowDigest: String?
    let elementIdentity: UInt
    let readableStateDigest: String?

    func sameTarget(as current: Self) -> Bool {
        guard processIdentifier == current.processIdentifier,
              elementIdentity == current.elementIdentity,
              role == current.role,
              subrole == current.subrole else {
            return false
        }
        if let bundleIdentifier, let currentBundleIdentifier = current.bundleIdentifier,
           bundleIdentifier != currentBundleIdentifier {
            return false
        }
        if let windowDigest, let currentWindowDigest = current.windowDigest,
           windowDigest != currentWindowDigest {
            return false
        }
        return true
    }

    func corresponds(to current: Self) -> Bool {
        guard sameTarget(as: current) else { return false }
        if let readableStateDigest, let currentStateDigest = current.readableStateDigest,
           readableStateDigest != currentStateDigest {
            return false
        }
        return true
    }

    static func digest(_ value: String) -> String {
        let bytes = Data(value.utf8.prefix(4_096))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
