#if !DEBUG
import AppKit
import Foundation

@MainActor
enum QualificationWorkflow {
    static func run(evidenceURL: URL) async {
        var evidence: [String: Any] = [
            "schemaVersion": 1,
            "offlineTranscription": false,
            "copyMode": false,
            "automaticInsertion": false,
            "readSelection": false,
            "modelDownloadAttempted": false,
            "networkAttempted": false,
            "postOperationCleanup": false,
        ]
        do {
            guard let resources = Bundle.main.resourceURL else { throw QualificationError.resourcesMissing }
            let model = resources.appendingPathComponent("models/ggml-large-v3-turbo-q5_0.bin")
            let vad = resources.appendingPathComponent("models/ggml-silero-v6.2.0.bin")
            let audio = resources.appendingPathComponent("qualification.wav")
            let session = LocalInferenceSession(
                executableURL: resources.appendingPathComponent("whisper-cli"),
                modelURL: model,
                vadModelURL: vad
            )
            _ = try await session.transcribe(
                audioURL: audio,
                declaredDuration: 1,
                language: "en",
                profileID: "qualification",
                coldStart: true
            )
            evidence["offlineTranscription"] = true

            let textService = MacTextService(accessibilityGranted: { true })
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSnapshot(pasteboard)
            textService.copy("qualification-copy")
            evidence["copyMode"] = pasteboard.string(forType: .string) == "qualification-copy"
            _ = snapshot.restore(to: pasteboard, ifChangeCountIs: pasteboard.changeCount)

            let adapter = QualificationTextAdapter(value: "controlled target", selectedRange: NSRange(location: 11, length: 6))
            let insertion = try await TextInsertionCoordinator(adapter: adapter).insert(
                "replacement",
                operationID: UUID(),
                persistCandidate: {}
            )
            evidence["automaticInsertion"] = insertion.receipt.isVerified

            let capabilities = SpeechCapabilityPolicy().requiredCapabilities(for: .readSelection)
            let chunks = MacTextService.speechChunksForQualification("controlled selection")
            evidence["readSelection"] = capabilities.contains(.selectedText) && chunks.count == 1
            evidence["postOperationCleanup"] = await session.lastReceipt?.cleanupSucceeded == true
        } catch {
            evidence["errorClass"] = String(describing: type(of: error))
        }
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]) {
            try? data.write(to: evidenceURL, options: .atomic)
        }
    }
}

private enum QualificationError: Error { case resourcesMissing }

private actor QualificationTextAdapter: TextInsertionAdapter {
    private var snapshot: InsertionTargetSnapshot

    init(value: String, selectedRange: NSRange) {
        snapshot = InsertionTargetSnapshot(
            fingerprint: .init(
                processIdentifier: 1,
                bundleIdentifier: "com.local.tk.qualification",
                role: "AXTextField",
                subrole: nil,
                windowDigest: "controlled",
                elementIdentity: 1,
                readableStateDigest: nil
            ),
            value: value,
            selectedRange: selectedRange,
            isSecure: false,
            isEnabled: true,
            isEditable: true,
            supportsDirectRangeMutation: true
        )
    }

    func captureTarget() -> InsertionTargetSnapshot? { snapshot }
    func readTarget() -> InsertionTargetSnapshot? { snapshot }

    func replace(range: NSRange, with text: String, in target: InsertionTargetSnapshot) -> Bool {
        let value = (snapshot.value as NSString).replacingCharacters(in: range, with: text)
        snapshot = InsertionTargetSnapshot(
            fingerprint: snapshot.fingerprint,
            value: value,
            selectedRange: NSRange(location: range.location + (text as NSString).length, length: 0),
            isSecure: false,
            isEnabled: true,
            isEditable: true,
            supportsDirectRangeMutation: true
        )
        return true
    }

    func paste(_ text: String, into target: InsertionTargetSnapshot) -> Bool { false }
}
#endif
