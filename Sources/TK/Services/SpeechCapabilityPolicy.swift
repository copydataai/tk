import Foundation

enum SpeechOperation: Sendable { case copyModeDictation, automaticInsertion, readSelection }
enum SpeechCapability: String, CaseIterable, Sendable { case microphone, accessibility, focusCapture, selectedText, syntheticEvents, clipboard }

protocol SpeechCapabilityAdapter: AnyObject {
    func request(_ capability: SpeechCapability) async -> Bool
    func perform(_ capability: SpeechCapability) async
}

struct SpeechCapabilityPolicy {
    func requiredCapabilities(for operation: SpeechOperation) -> Set<SpeechCapability> {
        switch operation {
        case .copyModeDictation:
            [.microphone]
        case .automaticInsertion:
            [.microphone, .accessibility, .focusCapture]
        case .readSelection:
            [.accessibility, .focusCapture, .selectedText]
        }
    }

    func authorize(_ operation: SpeechOperation, using adapter: SpeechCapabilityAdapter) async -> Bool {
        for capability in requiredCapabilities(for: operation) {
            guard await adapter.request(capability) else { return false }
        }
        return true
    }
}

struct ClipboardOwnershipToken: Equatable, Sendable {
    let changeCount: Int
    let temporaryValueDigest: String
}

struct ClipboardRestorationPolicy {
    func mayRestore(
        token: ClipboardOwnershipToken,
        currentChangeCount: Int,
        currentValue: String?
    ) -> Bool {
        token.changeCount == currentChangeCount
            && currentValue.map(InsertionTargetFingerprint.digest) == token.temporaryValueDigest
    }
}

struct ContentFreeDeletionReceipt: Codable, Equatable, Sendable {
    let storeCode: String
    let successCount: Int
    let failureCount: Int
    let sanitizedPathComponent: String?

    init(storeCode: String, successCount: Int, failureCount: Int, path: URL?) {
        self.storeCode = storeCode
        self.successCount = successCount
        self.failureCount = failureCount
        sanitizedPathComponent = path?.lastPathComponent
    }
}
