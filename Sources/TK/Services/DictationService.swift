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
    @ObservationIgnored private var isPreparing = false
    @ObservationIgnored private var isFinalizing = false
    @ObservationIgnored private var shouldTranscribe = false

    func toggle() {
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
            requestMicrophonePermission()
        }
    }

    func cancel() {
        guard isRecording else { return }
        shouldTranscribe = false
        stopRecording()
        status = "Dictation cancelled"
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startRecording()
                    } else {
                        self.status = "Microphone permission is required"
                    }
                }
            }
        default:
            status = "Microphone permission is required"
        }
    }

    private func startRecording() {
        isPreparing = true
        status = "Choosing a working microphone…"

        Task {
            do {
                let setup = try await Task.detached(priority: .userInitiated) {
                    try Self.prepareCapture()
                }.value
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
                UserDefaults.standard.set(setup.deviceID, forKey: "workingMicrophoneID")
                transcript = ""
                shouldTranscribe = false
                isRecording = true
                setup.output.startRecording(
                    to: url,
                    outputFileType: .caf,
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
        let session = captureSession
        captureSession = nil
        captureOutput = nil
        recordingDelegate = nil
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

        guard let executableURL = Bundle.main.url(forResource: "whisper-cli", withExtension: nil) else {
            try? FileManager.default.removeItem(at: recordingURL)
            isTranscribing = false
            status = "Whisper runtime is missing — build with script/build_and_run.sh"
            return
        }

        let modelDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tk/models")
        let modelURL = modelDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        let vadModelURL = modelDirectory.appendingPathComponent("ggml-silero-v6.2.0.bin")
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: vadModelURL.path) else {
            try? FileManager.default.removeItem(at: recordingURL)
            isTranscribing = false
            status = "Whisper models are missing — build with script/build_and_run.sh"
            return
        }

        status = "Transcribing locally…"

        Task {
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
                isTranscribing = false
            }
            do {
                let text = try await Task.detached {
                    try Self.transcribe(
                        recordingURL,
                        executableURL: executableURL,
                        modelURL: modelURL,
                        vadModelURL: vadModelURL
                    )
                }.value
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
        for device in devices {
            do {
                guard try probe(device) else { continue }
                let session = AVCaptureSession()
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureAudioFileOutput()
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
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MicrophoneError.noWorkingInput
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

    nonisolated private static func transcribe(
        _ recordingURL: URL,
        executableURL: URL,
        modelURL: URL,
        vadModelURL: URL
    ) throws -> String {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let wavURL = temporaryDirectory
            .appendingPathComponent("tk-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let outputURL = temporaryDirectory.appendingPathComponent("tk-\(UUID().uuidString)")
        let textURL = outputURL.appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: textURL)
        }

        try run(
            URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                recordingURL.path,
                wavURL.path,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
            ]
        )
        try run(
            executableURL,
            arguments: [
                "-m", modelURL.path,
                "-f", wavURL.path,
                "--vad",
                "-vm", vadModelURL.path,
                "-l", "auto",
                "-otxt",
                "-of", outputURL.path,
                "-np",
                "-nt",
            ]
        )

        return try String(contentsOf: textURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func run(_ executableURL: URL, arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperError.processFailed(
                message.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "\(executableURL.lastPathComponent) exited with status \(process.terminationStatus)"
            )
        }
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
    case configurationFailed
    case noWorkingInput

    var errorDescription: String? {
        switch self {
        case .configurationFailed:
            "The microphone could not be configured"
        case .noWorkingInput:
            "No connected microphone is producing audio"
        }
    }
}

private enum WhisperError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            message
        }
    }
}
