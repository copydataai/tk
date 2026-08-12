import CryptoKit
import Foundation

enum InsertionFailureReason: String, Equatable, Sendable {
    case accessibilityRequired
    case noFocusedControl
    case targetChanged
    case unsupportedControl
    case readbackMismatch
}

enum InsertionReceipt: Equatable, Sendable {
    case verified
    case attempted
    case copyOnly
    case failedRecoverable(InsertionFailureReason)

    static let targetMismatch = Self.failedRecoverable(.targetChanged)

    static func axWriteResult(
        writeSucceeded: Bool,
        readbackMatches: Bool?
    ) -> Self {
        guard writeSucceeded else { return .failedRecoverable(.unsupportedControl) }
        guard let readbackMatches else { return .attempted }
        return readbackMatches ? .verified : .failedRecoverable(.readbackMismatch)
    }

    static func pasteResult(eventPosted: Bool) -> Self {
        eventPosted ? .attempted : .copyOnly
    }

    var isVerified: Bool {
        self == .verified
    }

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

    func corresponds(to current: Self) -> Bool {
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
