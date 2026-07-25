import AppKit
import AVFoundation
import Foundation

actor WhisperRuntime {
    static let shared = WhisperRuntime()

    private var process: Process?
    private var serverURL: URL?
    private var terminationObserver: NSObjectProtocol?
    private var isStarting = false

    func transcribe(wavURL: URL, language: String = "auto") async throws -> String {
        let wavURL = try Self.validatedWAV(wavURL)
        guard !language.isEmpty,
              language.count <= 16,
              language.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else {
            throw WhisperRuntimeError.invalidLanguage
        }

        let serverURL = try await readyServerURL()
        let boundary = "tk-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"input.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: wavURL))
        body.append("\r\n")
        for (name, value) in [
            ("language", language),
            ("response_format", "json"),
            ("vad", "true"),
            ("no_timestamps", "true"),
        ] {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)--\r\n")

        var request = URLRequest(url: serverURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let response = response as? HTTPURLResponse else {
            throw WhisperRuntimeError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw WhisperRuntimeError.inferenceFailed(detail)
        }
        guard let text = try? JSONDecoder().decode(InferenceResponse.self, from: data).text else {
            throw WhisperRuntimeError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if process?.isRunning == true {
            process?.terminate()
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        try? FileManager.default.removeItem(at: Self.pidURL)
    }

    private func readyServerURL() async throws -> URL {
        if process?.isRunning == true, let serverURL {
            return serverURL
        }
        while isStarting {
            try await Task.sleep(for: .milliseconds(50))
            if process?.isRunning == true, let serverURL {
                return serverURL
            }
        }

        isStarting = true
        defer {
            isStarting = false
            if serverURL == nil {
                stopServer()
            }
        }
        stopServer()

        let resources = Bundle.main.resourceURL
        let executableURL = resources?.appendingPathComponent("whisper-server")
        let modelDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/models", isDirectory: true)
        let modelURL = modelDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        let vadModelURL = modelDirectory.appendingPathComponent("ggml-silero-v6.2.0.bin")
        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw WhisperRuntimeError.runtimeMissing
        }
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: vadModelURL.path) else {
            throw WhisperRuntimeError.modelsMissing
        }

        for _ in 0..<8 {
            let port = Int.random(in: 49_152...65_535)
            let url = URL(string: "http://127.0.0.1:\(port)")!
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "--model", modelURL.path,
                "--host", "127.0.0.1",
                "--port", String(port),
                "--language", "auto",
                "--vad",
                "--vad-model", vadModelURL.path,
                "--no-timestamps",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            self.process = process
            registerTerminationCleanup(for: process)
            try? String(process.processIdentifier).write(
                to: Self.pidURL,
                atomically: true,
                encoding: .utf8
            )

            if try await waitUntilReady(process: process, serverURL: url) {
                serverURL = url
                return url
            }
            stopServer()
        }
        throw WhisperRuntimeError.startupFailed
    }

    private func waitUntilReady(process: Process, serverURL: URL) async throws -> Bool {
        let deadline = Date().addingTimeInterval(120)
        let healthURL = serverURL.appendingPathComponent("health")
        while Date() < deadline {
            try Task.checkCancellation()
            guard process.isRunning else { return false }
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 1
            if let (data, response) = try? await URLSession.shared.data(for: request),
               process.isRunning,
               (response as? HTTPURLResponse)?.statusCode == 200,
               (try? JSONDecoder().decode(HealthResponse.self, from: data).status) == "ok" {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func registerTerminationCleanup(for process: Process) {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak process] _ in
            if process?.isRunning == true {
                process?.terminate()
            }
            try? FileManager.default.removeItem(at: Self.pidURL)
        }
    }

    private func stopServer() {
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        serverURL = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        try? FileManager.default.removeItem(at: Self.pidURL)
    }

    private nonisolated static func validatedWAV(_ url: URL) throws -> URL {
        let url = url.standardizedFileURL
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw WhisperRuntimeError.invalidAudio
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 12) ?? Data()
        let format = try AVAudioFile(forReading: url).fileFormat
        guard header.count == 12,
              String(data: header[0..<4], encoding: .ascii) == "RIFF",
              String(data: header[8..<12], encoding: .ascii) == "WAVE",
              format.sampleRate == 16_000,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16 else {
            throw WhisperRuntimeError.invalidAudio
        }
        return url
    }

    private nonisolated static var pidURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/whisper-server.pid")
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct InferenceResponse: Decodable {
    let text: String
}

private struct ServerError: Decodable {
    let error: String
}

private enum WhisperRuntimeError: LocalizedError {
    case invalidAudio
    case invalidLanguage
    case invalidResponse
    case inferenceFailed(String)
    case modelsMissing
    case runtimeMissing
    case startupFailed

    var errorDescription: String? {
        switch self {
        case .invalidAudio:
            "Whisper requires a local mono 16-bit 16 kHz WAV file"
        case .invalidLanguage:
            "The transcription language is invalid"
        case .invalidResponse:
            "Whisper returned an invalid response"
        case .inferenceFailed(let detail):
            "Whisper failed: \(detail)"
        case .modelsMissing:
            "Whisper models are missing — build with script/build_and_run.sh"
        case .runtimeMissing:
            "Whisper runtime is missing — build with script/build_and_run.sh"
        case .startupFailed:
            "Whisper could not start its local server"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
