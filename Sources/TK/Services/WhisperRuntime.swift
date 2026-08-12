import AVFoundation
import Foundation

actor WhisperRuntime {
    static let shared = WhisperRuntime()

    private static let maxAudioBytes = 64 * 1024 * 1024
    private static let maxDuration: TimeInterval = 15 * 60

    private var session: LocalInferenceSession?
    private var activeProfileID: String?
    private(set) var lastPerformanceReceipt: InferencePerformanceReceipt?
    private let probes: InferenceLiveProbes

    init(probes: InferenceLiveProbes = .production) {
        self.probes = probes
    }

    func invalidate() {
        session = nil
        activeProfileID = nil
    }

    func transcribe(
        wavURL: URL,
        language: String = "auto",
        artifact: SpeechArtifact,
        operationID: UUID = UUID()
    ) async throws -> String {
        let audio = try Self.validatedWAV(wavURL)
        guard !language.isEmpty,
              language.count <= 16,
              language.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else {
            throw WhisperRuntimeError.invalidLanguage
        }

        let coldStart = activeProfileID != artifact.profileID || session == nil
        let executableURL = try helperExecutableURL()
        let modelBytes = (try? artifact.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let admission = try admissionOutcome(
            duration: audio.duration,
            audioBytes: audio.byteCount,
            profileID: artifact.profileID,
            requiredMemoryBytes: UInt64(max(modelBytes, 0)) * 3,
            executableURL: executableURL
        )
        guard admission == .admitted else {
            throw WhisperRuntimeError.admissionDenied(String(describing: admission))
        }
        guard InferenceOperationOwnership.acquire() else { throw WhisperRuntimeError.inferenceBusy }
        defer { InferenceOperationOwnership.release() }
        let session = try inferenceSession(artifact: artifact, executableURL: executableURL)
        do {
            let text = try await session.transcribe(
                audioURL: audio.url,
                declaredDuration: audio.duration,
                language: language,
                operationID: operationID,
                profileID: artifact.profileID,
                coldStart: coldStart
            )
            lastPerformanceReceipt = await session.lastReceipt
            return text
        } catch is CancellationError {
            throw CancellationError()
        } catch LocalInferenceSession.Error.busy {
            throw WhisperRuntimeError.inferenceBusy
        } catch LocalInferenceSession.Error.runtimeMissing {
            throw WhisperRuntimeError.runtimeMissing
        } catch {
            throw WhisperRuntimeError.inferenceFailed(error.localizedDescription)
        }
    }

    func admissionOutcomeForTesting(requiredMemoryBytes: UInt64) throws -> InferenceAdmissionOutcome {
        try admissionOutcome(
            duration: 1,
            audioBytes: 1,
            profileID: "large-v3",
            requiredMemoryBytes: requiredMemoryBytes,
            executableURL: URL(fileURLWithPath: "/test/whisper-cli")
        )
    }

    private func admissionOutcome(
        duration: TimeInterval,
        audioBytes: Int,
        profileID: String,
        requiredMemoryBytes: UInt64,
        executableURL: URL
    ) throws -> InferenceAdmissionOutcome {
        let preflight: InferencePreflight
        do {
            preflight = InferencePreflight(
                duration: duration,
                audioBytes: audioBytes,
                audioFormat: "wav",
                availableMemoryBytes: try probes.availableMemoryBytes(),
                memoryPressure: try probes.memoryPressure(),
                helperAvailable: try probes.helperAvailable(executableURL),
                profile: .init(
                    profileID: profileID,
                    requiredMemoryBytes: requiredMemoryBytes,
                    device: "metal"
                ),
                activeOperations: try probes.activeOperations()
            )
        } catch {
            throw WhisperRuntimeError.admissionStateUnavailable
        }
        return InferenceAdmissionPolicy(
            maxDuration: Self.maxDuration,
            maxAudioBytes: Self.maxAudioBytes,
            allowedFormats: ["wav"],
            maxConcurrency: 1
        ).evaluate(preflight)
    }

    private func helperExecutableURL() throws -> URL {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("whisper-cli") else {
            throw WhisperRuntimeError.runtimeMissing
        }
        return url
    }

    private func inferenceSession(artifact: SpeechArtifact, executableURL: URL) throws -> LocalInferenceSession {
        if activeProfileID == artifact.profileID, let session {
            return session
        }
        let resources = Bundle.main.resourceURL
        let modelDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/models", isDirectory: true)
        let vadModelURL = Self.modelURL(
            named: "ggml-silero-v6.2.0.bin",
            resources: resources,
            fallbackDirectory: modelDirectory
        )
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw WhisperRuntimeError.runtimeMissing
        }
        guard FileManager.default.fileExists(atPath: artifact.url.path),
              FileManager.default.fileExists(atPath: vadModelURL.path) else {
            throw WhisperRuntimeError.modelsMissing
        }

        let session = LocalInferenceSession(
            executableURL: executableURL,
            modelURL: artifact.url,
            vadModelURL: vadModelURL
        )
        self.session = session
        activeProfileID = artifact.profileID
        return session
    }

    private nonisolated static func validatedWAV(_ url: URL) throws -> ValidatedAudio {
        let url = url.standardizedFileURL
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maxAudioBytes else {
            throw WhisperRuntimeError.invalidAudio
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 12) ?? Data()
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.fileFormat
        guard header.count == 12,
              String(data: header[0..<4], encoding: .ascii) == "RIFF",
              String(data: header[8..<12], encoding: .ascii) == "WAVE",
              format.sampleRate == 16_000,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16,
              audioFile.length > 0 else {
            throw WhisperRuntimeError.invalidAudio
        }
        let duration = Double(audioFile.length) / format.sampleRate
        guard duration <= maxDuration else { throw WhisperRuntimeError.invalidAudio }
        return ValidatedAudio(
            url: url,
            duration: duration,
            byteCount: fileSize
        )
    }

    private nonisolated static func modelURL(
        named name: String,
        resources: URL?,
        fallbackDirectory: URL
    ) -> URL {
        if let bundled = resources?.appendingPathComponent("models/\(name)"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return fallbackDirectory.appendingPathComponent(name)
    }
}

private struct ValidatedAudio {
    let url: URL
    let duration: TimeInterval
    let byteCount: Int
}

enum WhisperRuntimeError: LocalizedError, Equatable {
    case admissionStateUnavailable
    case inferenceBusy
    case inferenceFailed(String)
    case admissionDenied(String)
    case invalidAudio
    case invalidLanguage
    case modelsMissing
    case runtimeMissing

    var errorDescription: String? {
        switch self {
        case .admissionStateUnavailable:
            "Current inference admission state is unavailable; try again"
        case .inferenceBusy:
            "Whisper is already processing a dictation"
        case .inferenceFailed(let detail):
            "Whisper failed: \(detail)"
        case .admissionDenied(let detail):
            "The selected dictation profile was not admitted: \(detail)"
        case .invalidAudio:
            "Whisper requires a local mono 16-bit 16 kHz WAV file"
        case .invalidLanguage:
            "The transcription language is invalid"
        case .modelsMissing:
            "Whisper models are missing - build with script/build_and_run.sh"
        case .runtimeMissing:
            "Whisper runtime is missing - build with script/build_and_run.sh"
        }
    }
}
