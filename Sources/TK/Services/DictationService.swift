@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DictationService {
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    private(set) var transcript = ""
    private(set) var status = "Press the shortcut to dictate"

    var onTranscriptReady: ((String) -> Void)?

    @ObservationIgnored private var captureSession: AVCaptureSession?
    @ObservationIgnored private var captureOutput: AVCaptureAudioFileOutput?
    @ObservationIgnored private var recordingDelegate: RecordingDelegate?
    @ObservationIgnored private var recordingLanguage: String?
    @ObservationIgnored private var isPreparing = false
    @ObservationIgnored private var isFinalizing = false
    @ObservationIgnored private var shouldTranscribe = false

    func toggle(language: String? = nil) {
        guard !isTranscribing else {
            status = "Transcription is still running"
            return
        }
        guard !isPreparing, !isFinalizing else {
            status = "The microphone is still getting ready"
            return
        }
        if isRecording {
            finish()
        } else {
            requestMicrophonePermission(language: language)
        }
    }

    func cancel() {
        guard isRecording else { return }
        shouldTranscribe = false
        stopRecording()
        status = "Dictation cancelled"
    }

    private func requestMicrophonePermission(language: String?) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording(language: language)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startRecording(language: language)
                    } else {
                        self.status = "Microphone permission is required"
                    }
                }
            }
        default:
            status = "Microphone permission is required"
        }
    }

    private func startRecording(language: String?) {
        isPreparing = true
        status = "Choosing a working microphone…"

        Task {
            do {
                let setup = try await Task.detached(priority: .userInitiated) {
                    try Self.prepareCapture()
                }.value
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tk-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                let delegate = RecordingDelegate { [weak self] url, error in
                    Task { @MainActor in
                        self?.recordingDidFinish(at: url, error: error)
                    }
                }

                captureSession = setup.session
                captureOutput = setup.output
                recordingDelegate = delegate
                recordingLanguage = language
                UserDefaults.standard.set(setup.deviceID, forKey: "workingMicrophoneID")
                transcript = ""
                shouldTranscribe = false
                isRecording = true
                setup.output.startRecording(
                    to: url,
                    outputFileType: .wav,
                    recordingDelegate: delegate
                )
                status = "Listening on \(setup.deviceName) — press the shortcut again to insert"
            } catch {
                status = "Could not start the microphone: \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }

    private func finish() {
        guard isRecording else { return }
        shouldTranscribe = true
        isTranscribing = true
        status = "Finishing recording…"
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        isFinalizing = true
        captureOutput?.stopRecording()
    }

    private func recordingDidFinish(at recordingURL: URL, error: Error?) {
        let shouldTranscribe = shouldTranscribe
        let language = recordingLanguage
        let session = captureSession
        captureSession = nil
        captureOutput = nil
        recordingDelegate = nil
        recordingLanguage = nil
        self.shouldTranscribe = false
        isFinalizing = false
        Task.detached { session?.stopRunning() }

        guard shouldTranscribe else {
            try? FileManager.default.removeItem(at: recordingURL)
            return
        }
        guard Self.recordingSucceeded(error) else {
            try? FileManager.default.removeItem(at: recordingURL)
            isTranscribing = false
            status = "Could not record audio: \(error!.localizedDescription)"
            return
        }

        status = "Transcribing locally…"

        Task {
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
                isTranscribing = false
            }
            do {
                let text = try await WhisperRuntime.shared.transcribe(
                    wavURL: recordingURL,
                    language: language ?? "auto"
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

    nonisolated private static func prepareCapture() throws -> CaptureSetup {
        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.wav) else {
            throw MicrophoneError.audioFormatUnsupported
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let savedID = UserDefaults.standard.string(forKey: "workingMicrophoneID")
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let devices = discovery.devices
            .filter { $0.isConnected && !$0.isSuspended }
            .sorted {
                devicePriority($0.uniqueID, savedID: savedID, defaultID: defaultID)
                    < devicePriority($1.uniqueID, savedID: savedID, defaultID: defaultID)
            }

        assert(
            isWorkingInput(level: -55) && !isWorkingInput(level: -758),
            "A live microphone must win over a device producing digital silence"
        )

        var lastError: Error?
        if let savedDevice = devices.first(where: { $0.uniqueID == savedID }) {
            do {
                return try configure(savedDevice)
            } catch {
                lastError = error
            }
        }

        for device in devices {
            do {
                guard try probe(device) else { continue }
                return try configure(device)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MicrophoneError.noWorkingInput
    }

    nonisolated private static func configure(_ device: AVCaptureDevice) throws -> CaptureSetup {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioFileOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw MicrophoneError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        return CaptureSetup(
            session: session,
            output: output,
            deviceID: device.uniqueID,
            deviceName: device.localizedName
        )
    }

    nonisolated private static func probe(_ device: AVCaptureDevice) throws -> Bool {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        let sink = AudioProbeSink()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw MicrophoneError.configurationFailed
        }
        output.setSampleBufferDelegate(
            sink,
            queue: DispatchQueue(label: "tk.microphone-probe")
        )
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        Thread.sleep(forTimeInterval: 0.35)
        let level = output.connection(with: .audio)?
            .audioChannels
            .map(\.peakHoldLevel)
            .max() ?? -.infinity
        session.stopRunning()
        output.setSampleBufferDelegate(nil, queue: nil)
        return sink.receivedSamples && isWorkingInput(level: level)
    }

    nonisolated private static func devicePriority(
        _ deviceID: String,
        savedID: String?,
        defaultID: String?
    ) -> Int {
        if deviceID == savedID { return 0 }
        if deviceID == defaultID { return 1 }
        return 2
    }

    nonisolated private static func isWorkingInput(level: Float) -> Bool {
        level > -120
    }

    nonisolated private static func recordingSucceeded(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return true }
        return error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
    }
}

private struct CaptureSetup: @unchecked Sendable {
    let session: AVCaptureSession
    let output: AVCaptureAudioFileOutput
    let deviceID: String
    let deviceName: String
}

private final class AudioProbeSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var didReceiveSamples = false

    var receivedSamples: Bool {
        lock.withLock { didReceiveSamples }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.withLock { didReceiveSamples = true }
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

private enum MicrophoneError: LocalizedError {
    case audioFormatUnsupported
    case configurationFailed
    case noWorkingInput

    var errorDescription: String? {
        switch self {
        case .audioFormatUnsupported:
            "This Mac cannot record Whisper-compatible WAV audio"
        case .configurationFailed:
            "The microphone could not be configured"
        case .noWorkingInput:
            "No connected microphone is producing audio"
        }
    }
}
