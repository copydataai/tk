@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DictationService {
    private var activity: DictationActivity { DictationActivity(transaction: transaction) }
    private(set) var transaction: DictationTransaction?
    var isRecording: Bool { activity.isRecording }
    var isTranscribing: Bool { activity.isTranscribing }
    private(set) var transcript = ""
    private(set) var status = "Press the shortcut to dictate"
    private(set) var activeProfileID: String?
    private(set) var lastStartMilliseconds: Double?
    private let pendingStore: PendingDictationStore
    private let operationJournal: OperationJournal
    private let artifactCleaner: OperationArtifactCleaner
    private(set) var pendingResult: PendingDictation?
    private(set) var pendingStoreError: Error?
    private(set) var operationJournalError: Error?
    private(set) var artifactCleanupReport: OperationArtifactCleanupReport
    private(set) var preservedAudioURL: URL?
    private(set) var lastContinuityNotification: ContinuityNotification?

    var onTranscriptReady: ((String) -> Void)?
    var onCommitCandidate: ((UUID, String) -> Void)?
    var resolveArtifact: ((String) throws -> SpeechArtifact)?
    var onContinuityNotification: ((ContinuityNotification, String) -> Void)?

    @ObservationIgnored private var captureSession: AVCaptureSession?
    @ObservationIgnored private var captureOutput: AVCaptureAudioFileOutput?
    @ObservationIgnored private var recordingDelegate: RecordingDelegate?
    @ObservationIgnored private var recordingLanguage: String?
    @ObservationIgnored private var capturedDeviceID: String?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    var isPreparing: Bool { activity.isPreparing }
    var isFinalizing: Bool { activity.isFinalizing }
    @ObservationIgnored private var preparationID: UUID?
    @ObservationIgnored private var preparationStartedAt: ContinuousClock.Instant?

    init(
        pendingStore: PendingDictationStore? = nil,
        operationJournal: OperationJournal? = nil,
        artifactCleaner: OperationArtifactCleaner = OperationArtifactCleaner(),
        transaction: DictationTransaction? = nil
    ) {
        self.artifactCleaner = artifactCleaner
        self.transaction = transaction
        do {
            if let operationJournal {
                self.operationJournal = operationJournal
            } else if pendingStore != nil {
                self.operationJournal = OperationJournal(fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tk-operation-\(UUID().uuidString).json"))
            } else {
                self.operationJournal = try OperationJournal.applicationSupport()
            }
        } catch {
            self.operationJournal = OperationJournal(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("tk-unavailable-operation-journal"))
            operationJournalError = error
        }
        artifactCleanupReport = artifactCleaner.cleanupStale()
        let resolvedStore: PendingDictationStore
        do {
            resolvedStore = try pendingStore ?? PendingDictationStore.applicationSupport()
        } catch {
            resolvedStore = PendingDictationStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tk-unavailable-pending-dictation")
            )
            pendingStoreError = error
        }
        self.pendingStore = resolvedStore
        guard pendingStoreError == nil else { return }
        do {
            pendingResult = try resolvedStore.load()
        } catch {
            pendingStoreError = error
        }
        do {
            if let recovery = try self.operationJournal.recover(), recovery.latest.verifiedInsertion {
                try resolvedStore.discard()
                pendingResult = nil
            }
        } catch {
            operationJournalError = error
        }
    }

    func toggle(language: String? = nil, artifact: SpeechArtifact? = nil) {
        guard !isTranscribing else {
            status = "Transcription is still running"
            return
        }
        if isPreparing {
            cancelPreparation()
            return
        }
        guard !isFinalizing else {
            status = "The recording is still finishing"
            return
        }
        if isRecording {
            finish()
        } else {
            guard let artifact else {
                status = "Choose an available dictation profile in Settings"
                return
            }
            activeProfileID = artifact.profileID
            requestMicrophonePermission(language: language, artifact: artifact)
        }
    }

    func showUnavailable(_ message: String) {
        status = message
    }

    func cancel() {
        if isPreparing {
            cancelPreparation()
            return
        }
        if isRecording {
            stopRecording(shouldTranscribe: false)
            status = "Dictation cancelled"
            return
        }
        guard let state = transaction?.state,
              [.recording, .finalizing, .recognizing].contains(state) else { return }
        transition(to: .cancelled)
        status = "Dictation cancelled"
    }

    private func requestMicrophonePermission(language: String?, artifact: SpeechArtifact) {
        let operationID = UUID()
        preparationID = operationID
        preparationStartedAt = .now
        transaction = DictationTransaction(
            operationID: operationID,
            profileID: artifact.profileID
        )
        try? record(.capture, operationID: operationID, retention: .temporaryAudio, reason: .started)
        status = "Waiting for microphone access…"
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording(
                language: language,
                profileID: artifact.profileID,
                operationID: operationID
            )
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.preparationID == operationID else { return }
                    if granted {
                        self.startRecording(
                            language: language,
                            profileID: artifact.profileID,
                            operationID: operationID
                        )
                    } else {
                        self.preparationID = nil
                        self.fail(
                            kind: .permission,
                            message: "Microphone permission is required",
                            recoverable: true
                        )
                        self.activeProfileID = nil
                        self.status = "Microphone permission is required"
                    }
                }
            }
        default:
            preparationID = nil
            fail(
                kind: .permission,
                message: "Microphone permission is required",
                recoverable: true
            )
            activeProfileID = nil
            status = "Microphone permission is required"
        }
    }

    private func startRecording(language: String?, profileID: String, operationID: UUID) {
        guard preparationID == operationID else { return }
        status = "Choosing a working microphone…"

        Task {
            do {
                let setup = try await Task.detached(priority: .userInitiated) {
                    try MicrophoneCapture.prepare()
                }.value
                guard preparationID == operationID else {
                    Task.detached { setup.session.stopRunning() }
                    return
                }
                let artifacts = try artifactCleaner.createOperation(operationID: operationID)
                let delegate = RecordingDelegate { [weak self] url, error in
                    Task { @MainActor in
                        self?.recordingDidFinish(at: url, error: error)
                    }
                }

                captureSession = setup.session
                captureOutput = setup.output
                capturedDeviceID = setup.deviceID
                recordingDelegate = delegate
                recordingLanguage = language
                activeProfileID = profileID
                UserDefaults.standard.set(setup.deviceID, forKey: "workingMicrophoneID")
                transcript = ""
                transaction?.setAudioState(.capturing)
                transition(to: .recording)
                if let preparationStartedAt {
                    lastStartMilliseconds = preparationStartedAt.duration(to: .now).dictationMilliseconds
                }
                MicrophoneCapture.apply(.production, to: setup.output)
                setup.output.startRecording(
                    to: artifacts.recordingURL,
                    outputFileType: .caf,
                    recordingDelegate: delegate
                )
                status = "Listening on \(setup.deviceName) — press the shortcut again to insert"
            } catch {
                guard preparationID == operationID else { return }
                artifactCleaner.removeOperation(operationID: operationID)
                activeProfileID = nil
                fail(kind: .capture, message: error.localizedDescription, recoverable: true)
                status = "Could not start the microphone: \(error.localizedDescription)"
            }
            if preparationID == operationID {
                preparationID = nil
                preparationStartedAt = nil
            }
        }
    }

    private func cancelPreparation() {
        preparationID = nil
        preparationStartedAt = nil
        transition(to: .cancelled)
        activeProfileID = nil
        status = "Dictation cancelled"
    }

    private func finish() {
        guard isRecording else { return }
        status = "Finishing recording…"
        stopRecording(shouldTranscribe: true)
    }

    private func stopRecording(shouldTranscribe: Bool) {
        transition(to: .finalizing)
        if !shouldTranscribe {
            transition(to: .cancelled)
        }
        captureOutput?.stopRecording()
    }

    private func recordingDidFinish(at recordingURL: URL, error: Error?) {
        let shouldTranscribe = transaction?.state == .finalizing
        let language = recordingLanguage
        let profileID = activeProfileID
        let session = captureSession
        captureSession = nil
        captureOutput = nil
        capturedDeviceID = nil
        recordingDelegate = nil
        recordingLanguage = nil
        Task.detached { session?.stopRunning() }

        guard shouldTranscribe else {
            if let operationID = transaction?.operationID {
                artifactCleaner.removeOperation(operationID: operationID)
            }
            transaction?.setAudioState(.discarded)
            activeProfileID = nil
            return
        }
        guard MicrophoneCapture.recordingSucceeded(error) else {
            if let operationID = transaction?.operationID {
                artifactCleaner.removeOperation(operationID: operationID)
            }
            transaction?.setAudioState(.discarded)
            fail(kind: .capture, message: error!.localizedDescription, recoverable: true)
            activeProfileID = nil
            status = "Could not record audio: \(error!.localizedDescription)"
            return
        }

        status = "Transcribing locally…"
        transaction?.setAudioState(.available(recordingURL))
        transition(to: .recognizing)
        let operationID = transaction?.operationID

        recognitionTask = Task {
            guard let operationID else { return }
            let wavURL = recordingURL.deletingLastPathComponent().appendingPathComponent("speech.wav")
            defer {
                if !MicrophoneCapture.shouldRetainOperationAudio(
                    recordingURL: recordingURL,
                    preservedAudioURL: preservedAudioURL
                ) {
                    artifactCleaner.removeOperation(operationID: operationID)
                    transaction?.setAudioState(.discarded)
                }
                activeProfileID = nil
                recognitionTask = nil
            }
            do {
                guard transaction?.operationID == operationID,
                      transaction?.state == .recognizing else { return }
                guard let profileID, let resolveArtifact else {
                    throw SpeechProfileError.unavailable(
                        "The selected dictation profile is unavailable. Choose another profile in Settings."
                    )
                }
                let artifact = try resolveArtifact(profileID)
                try record(.inference, operationID: operationID, retention: .temporaryAudio, reason: .started)
                try await Task.detached {
                    try MicrophoneCapture.convertToWhisperWAV(recordingURL, outputURL: wavURL)
                }.value
                let text = try await WhisperRuntime.shared.transcribe(
                    wavURL: wavURL,
                    language: language ?? "auto",
                    artifact: artifact
                )
                guard transaction?.operationID == operationID,
                      transaction?.state == .recognizing else { return }
                transcript = text
                try transaction?.setCandidateText(text)
                if text.isEmpty {
                    transition(to: .discarded)
                    status = "Nothing heard"
                } else {
                    onTranscriptReady?(text)
                    onCommitCandidate?(operationID, text)
                    status = "Transcription ready"
                }
            } catch is CancellationError {
            } catch {
                if transaction?.operationID == operationID,
                   transaction?.state == .recognizing {
                    fail(kind: .recognition, message: error.localizedDescription, recoverable: true)
                }
                status = "Dictation failed: \(error.localizedDescription)"
            }
        }
    }

    func handleContinuityEvent(_ event: SystemContinuityEvent) {
        if ContinuityPolicy.requiresDeviceReprobe(after: event) {
            Task { await WhisperRuntime.shared.invalidate() }
        }
        let decision = ContinuityPolicy.decision(
            for: event,
            transactionState: transaction?.state,
            capturedDeviceID: capturedDeviceID
        )
        switch decision {
        case .continueCurrentOperation:
            return
        case .continueDegraded(let message):
            status = message
            notify(.degraded, message: message)
        case .interruptRecoverably(let message, let preserveAudio):
            let reportedMessage = interruptContinuity(message: message, preserveAudio: preserveAudio)
            notify(.interruptedRecoverable, message: reportedMessage)
        case .resourceBlocked(let message, let preserveAudio):
            let reportedMessage = interruptContinuity(
                message: message,
                preserveAudio: preserveAudio,
                resourceBlocked: true
            )
            notify(.resourceBlocked, message: reportedMessage)
        }
    }

    private func interruptContinuity(
        message: String,
        preserveAudio: Bool,
        resourceBlocked: Bool = false
    ) -> String {
        guard let state = transaction?.state,
              [.preparing, .recording, .finalizing, .recognizing].contains(state) else { return message }

        preparationID = nil
        preparationStartedAt = nil
        if preserveAudio,
           case .available(let url) = transaction?.audioState,
           FileManager.default.fileExists(atPath: url.path) {
            preservedAudioURL = url
        } else {
            preservedAudioURL = nil
        }
        let reportedMessage = preserveAudio && preservedAudioURL == nil
            ? message.replacingOccurrences(
                of: "Audio was preserved for recovery.",
                with: "The captured audio could not be preserved."
            )
            : message
        if resourceBlocked {
            fail(kind: .resourceBlocked, message: reportedMessage, recoverable: true)
        } else {
            do {
                try transaction?.interruptRecoverably(message: reportedMessage)
            } catch {
                assertionFailure("Invalid continuity interruption: \(error)")
            }
        }
        recognitionTask?.cancel()
        if state == .recording || state == .finalizing {
            captureOutput?.stopRecording()
        } else if state == .recognizing, let operationID = transaction?.operationID {
            preservedAudioURL = nil
            artifactCleaner.removeOperation(operationID: operationID)
            transaction?.setAudioState(.discarded)
        } else if state == .preparing, let operationID = transaction?.operationID {
            artifactCleaner.removeOperation(operationID: operationID)
            transaction?.setAudioState(.discarded)
        }
        activeProfileID = nil
        status = reportedMessage
        return reportedMessage
    }

    private func notify(_ notification: ContinuityNotification, message: String) {
        lastContinuityNotification = notification
        onContinuityNotification?(notification, message)
    }

    func beginCommit(operationID: UUID) {
        guard transaction?.operationID == operationID else { return }
        transition(to: .committing)
    }

    func completeCommit(operationID: UUID) {
        guard transaction?.operationID == operationID else { return }
        transition(to: .retained)
    }

    func failCommit(operationID: UUID, message: String) {
        guard transaction?.operationID == operationID else { return }
        fail(kind: .insertion, message: message, recoverable: true)
    }

    func acceptRecognizedCandidate(
        operationID: UUID,
        text: String,
        profileID: String,
        createdAt: Date = Date()
    ) {
        var restored = DictationTransaction(
            operationID: operationID,
            profileID: profileID,
            startedAt: createdAt
        )
        try? restored.transition(to: .recording, at: createdAt)
        try? restored.transition(to: .finalizing, at: createdAt)
        try? restored.transition(to: .recognizing, at: createdAt)
        try? restored.setCandidateText(text, at: createdAt)
        transaction = restored
        transcript = text
        try? record(.inference, operationID: operationID, content: text, retention: .temporaryAudio, reason: .completed)
        try? record(.pendingResult, operationID: operationID, content: text, retention: .pendingText, reason: .completed)
    }

    func persistCandidate(operationID: UUID) throws {
        guard let transaction,
              transaction.operationID == operationID,
              let text = transaction.candidateText else { return }
        let pending = PendingDictation(
            operationID: operationID,
            text: text,
            createdAt: transaction.startedAt,
            profileID: transaction.profileID,
            trust: .locallyRecognized,
            commitState: .ready
        )
        try pendingStore.save(pending)
        pendingResult = pending
        pendingStoreError = nil
        try record(.pendingResult, operationID: operationID, content: text, retention: .pendingText, reason: .completed)
    }

    func copyPendingResult(copy: (String) -> Void) throws -> InsertionReceipt {
        guard let transaction else { return .copyOnly }
        try persistCandidate(operationID: transaction.operationID)
        guard let pendingResult else { return .copyOnly }
        try record(.copy, operationID: pendingResult.operationID, content: pendingResult.text, retention: .clipboardExposed, reason: .userRequested)
        copy(pendingResult.text)
        return .copyOnly
    }

    func commitCandidate(
        operationID: UUID,
        disposition: (String) async -> InsertionReceipt
    ) async throws -> InsertionReceipt {
        try persistCandidate(operationID: operationID)
        guard var pending = pendingResult, pending.operationID == operationID else {
            return .failedRecoverable(.noFocusedControl)
        }
        pending.commitState = .inserting
        try pendingStore.save(pending)
        pendingResult = pending
        try record(.destinationChoice, operationID: operationID, content: pending.text, retention: .pendingText, reason: .userRequested)
        try record(.insertionAttempt, operationID: operationID, content: pending.text, retention: .pendingText, reason: .started)
        beginCommit(operationID: operationID)
        let receipt = await disposition(pending.text)
        if receipt.isVerified {
            try record(.verification, operationID: operationID, content: pending.text, retention: .pendingText, reason: .completed, verifiedInsertion: true)
            try pendingStore.discard()
            pendingResult = nil
            completeCommit(operationID: operationID)
            try record(.commit, operationID: operationID, content: pending.text, retention: .retainedHistory, reason: .completed, verifiedInsertion: true)
            return receipt
        }
        pending.commitState = .insertionFailed
        try pendingStore.save(pending)
        pendingResult = pending
        try record(.verification, operationID: operationID, content: pending.text, retention: .pendingText, reason: .mismatch)
        failCommit(operationID: operationID, message: receipt.diagnostic)
        return receipt
    }

    func retryPendingResult(
        disposition: (String, UUID) async -> InsertionReceipt
    ) async throws -> InsertionReceipt {
        guard var pending = pendingResult else {
            return .failedRecoverable(.noFocusedControl)
        }
        if try operationJournal.recover()?.latest.verifiedInsertion == true {
            try pendingStore.discard()
            pendingResult = nil
            return .failedRecoverable(.targetChanged)
        }
        try record(.retry, operationID: pending.operationID, content: pending.text, retention: .pendingText, reason: .userRequested)
        pending.commitState = .inserting
        try pendingStore.save(pending)
        pendingResult = pending
        beginCommit(operationID: pending.operationID)
        let receipt = await disposition(pending.text, pending.operationID)
        if receipt.verifiedInsertion?.operationID == pending.operationID {
            try record(.verification, operationID: pending.operationID, content: pending.text, retention: .pendingText, reason: .completed, verifiedInsertion: true)
            try pendingStore.discard()
            pendingResult = nil
            completeCommit(operationID: pending.operationID)
            try record(.commit, operationID: pending.operationID, content: pending.text, retention: .retainedHistory, reason: .completed, verifiedInsertion: true)
            return receipt
        }
        pending.commitState = .insertionFailed
        try pendingStore.save(pending)
        pendingResult = pending
        try record(.verification, operationID: pending.operationID, content: pending.text, retention: .pendingText, reason: .mismatch)
        failCommit(operationID: pending.operationID, message: receipt.diagnostic)
        return receipt
    }

    func discardPendingResult() throws {
        if let pendingResult {
            try record(.discard, operationID: pendingResult.operationID, content: pendingResult.text, retention: .discarded, reason: .userRequested)
        }
        try pendingStore.discard()
        pendingResult = nil
        pendingStoreError = nil
    }

    var pendingDeletionArtifact: DeletionArtifact {
        pendingStore.deletionArtifact
    }

    func acknowledgePendingArtifactDeletion() {
        pendingResult = nil
        pendingStoreError = nil
    }

    func updatePendingText(_ text: String) throws {
        guard var pending = pendingResult else { return }
        pending.text = text
        try pendingStore.save(pending)
        pendingResult = pending
        try record(.pendingResult, operationID: pending.operationID, content: text, retention: .pendingText, reason: .userRequested)
    }

    private func transition(to state: DictationTransaction.State) {
        do {
            try transaction?.transition(to: state)
        } catch {
            assertionFailure("Invalid dictation transaction transition: \(error)")
        }
    }

    private func record(
        _ phase: OperationPhase,
        operationID: UUID,
        content: String? = nil,
        retention: RetentionDisposition,
        reason: OperationReasonCode,
        verifiedInsertion: Bool = false
    ) throws {
        let latest = try operationJournal.entries().last
        let sameOperation = latest?.operationID == operationID
        let version = sameOperation ? (latest?.version ?? 0) + 1 : 1
        try operationJournal.append(.init(
            operationID: operationID,
            version: version,
            predecessorVersion: sameOperation ? latest?.version : nil,
            phase: phase,
            content: content,
            retention: retention,
            reason: reason,
            verifiedInsertion: verifiedInsertion
        ))
    }

    private func fail(
        kind: DictationTransaction.Failure.Kind,
        message: String,
        recoverable: Bool
    ) {
        do {
            try transaction?.fail(
                .init(kind: kind, message: message),
                recoverable: recoverable
            )
        } catch {
            assertionFailure("Invalid dictation transaction failure: \(error)")
        }
    }

}

private extension Duration {
    var dictationMilliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let onFinish: (URL, Error?) -> Void

    init(onFinish: @escaping (URL, Error?) -> Void) {
        self.onFinish = onFinish
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        onFinish(outputFileURL, error)
    }
}
