@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DictationService {
    private var activity = DictationActivity()
    var isRecording: Bool { activity.isRecording }
    var isTranscribing: Bool { activity.isTranscribing }
    private(set) var transcript = ""
    private(set) var status = "Press the shortcut to dictate"
    private(set) var activeProfileID: String?

    var onTranscriptReady: ((String) -> Void)?
    var resolveArtifact: ((String) throws -> SpeechArtifact)?

    @ObservationIgnored private var captureSession: AVCaptureSession?
    @ObservationIgnored private var captureOutput: AVCaptureAudioFileOutput?
    @ObservationIgnored private var recordingDelegate: RecordingDelegate?
    @ObservationIgnored private var recordingLanguage: String?
    var isPreparing: Bool { activity.isPreparing }
    var isFinalizing: Bool { activity.isFinalizing }
    @ObservationIgnored private var preparationID: UUID?

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
        guard isRecording else { return }
        stopRecording(shouldTranscribe: false)
        status = "Dictation cancelled"
    }

    private func requestMicrophonePermission(language: String?, artifact: SpeechArtifact) {
        let operationID = UUID()
        preparationID = operationID
        activity.beginPreparing()
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
                        self.activity.cancelPreparation()
                        self.activeProfileID = nil
                        self.status = "Microphone permission is required"
                    }
                }
            }
        default:
            preparationID = nil
            activity.cancelPreparation()
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
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tk-\(UUID().uuidString)")
                    .appendingPathExtension("caf")
                let delegate = RecordingDelegate { [weak self] url, error in
                    Task { @MainActor in
                        self?.recordingDidFinish(at: url, error: error)
                    }
                }

                captureSession = setup.session
                captureOutput = setup.output
                recordingDelegate = delegate
                recordingLanguage = language
                activeProfileID = profileID
                UserDefaults.standard.set(setup.deviceID, forKey: "workingMicrophoneID")
                transcript = ""
                activity.beginRecording()
                setup.output.startRecording(
                    to: url,
                    outputFileType: .caf,
                    recordingDelegate: delegate
                )
                status = "Listening on \(setup.deviceName) — press the shortcut again to insert"
            } catch {
                guard preparationID == operationID else { return }
                activeProfileID = nil
                status = "Could not start the microphone: \(error.localizedDescription)"
            }
            if preparationID == operationID {
                preparationID = nil
                activity.cancelPreparation()
            }
        }
    }

    private func cancelPreparation() {
        preparationID = nil
        activity.cancelPreparation()
        activeProfileID = nil
        status = "Dictation cancelled"
    }

    private func finish() {
        guard isRecording else { return }
        status = "Finishing recording…"
        stopRecording(shouldTranscribe: true)
    }

    private func stopRecording(shouldTranscribe: Bool) {
        activity.finishRecording(shouldTranscribe: shouldTranscribe)
        captureOutput?.stopRecording()
    }

    private func recordingDidFinish(at recordingURL: URL, error: Error?) {
        let shouldTranscribe = activity.completeRecording()
        let language = recordingLanguage
        let profileID = activeProfileID
        let session = captureSession
        captureSession = nil
        captureOutput = nil
        recordingDelegate = nil
        recordingLanguage = nil
        Task.detached { session?.stopRunning() }

        guard shouldTranscribe else {
            try? FileManager.default.removeItem(at: recordingURL)
            activeProfileID = nil
            return
        }
        guard MicrophoneCapture.recordingSucceeded(error) else {
            try? FileManager.default.removeItem(at: recordingURL)
            activity.completeTranscription()
            activeProfileID = nil
            status = "Could not record audio: \(error!.localizedDescription)"
            return
        }

        status = "Transcribing locally…"

        Task {
            let wavURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tk-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
                try? FileManager.default.removeItem(at: wavURL)
                activity.completeTranscription()
                activeProfileID = nil
            }
            do {
                guard let profileID, let resolveArtifact else {
                    throw SpeechProfileError.unavailable(
                        "The selected dictation profile is unavailable. Choose another profile in Settings."
                    )
                }
                let artifact = try resolveArtifact(profileID)
                try await Task.detached {
                    try MicrophoneCapture.convertToWhisperWAV(recordingURL, outputURL: wavURL)
                }.value
                let text = try await WhisperRuntime.shared.transcribe(
                    wavURL: wavURL,
                    language: language ?? "auto",
                    artifact: artifact
                )
                transcript = text
                if text.isEmpty {
                    status = "Nothing heard"
                } else {
                    onTranscriptReady?(text)
                    status = "Transcription ready"
                }
            } catch {
                status = "Dictation failed: \(error.localizedDescription)"
            }
        }
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
