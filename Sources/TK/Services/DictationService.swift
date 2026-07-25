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

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var recordingURL: URL?

    func toggle() {
        guard !isTranscribing else {
            status = "Transcription is still running"
            return
        }
        if isRecording {
            finish()
        } else {
            requestMicrophonePermission()
        }
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
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = "No microphone input is available"
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                do {
                    try file.write(from: buffer)
                } catch {
                    NSLog("tk could not record audio: %@", error.localizedDescription)
                }
            }
            audioFile = file
            recordingURL = url
            transcript = ""
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            status = "Listening — press the shortcut again to insert"
        } catch {
            inputNode.removeTap(onBus: 0)
            try? FileManager.default.removeItem(at: url)
            audioFile = nil
            recordingURL = nil
            status = "Could not start the microphone: \(error.localizedDescription)"
        }
    }

    private func finish() {
        guard isRecording, let recordingURL else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        self.recordingURL = nil
        isRecording = false

        guard let executableURL = Bundle.main.url(forResource: "whisper-cli", withExtension: nil) else {
            try? FileManager.default.removeItem(at: recordingURL)
            status = "Whisper runtime is missing — build with script/build_and_run.sh"
            return
        }

        let modelURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tk/models/ggml-large-v3-turbo-q5_0.bin")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            try? FileManager.default.removeItem(at: recordingURL)
            status = "Whisper model is missing — build with script/build_and_run.sh"
            return
        }

        isTranscribing = true
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
                        modelURL: modelURL
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

    nonisolated private static func transcribe(
        _ recordingURL: URL,
        executableURL: URL,
        modelURL: URL
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

private enum WhisperError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            message
        }
    }
}
