import Darwin
import Foundation

actor LocalInferenceSession {
    struct Limits: Sendable {
        let maxAudioBytes: Int
        let maxDuration: TimeInterval
        let maxResponseBytes: Int
        let timeout: TimeInterval

        static let production = Self(
            maxAudioBytes: 64 * 1024 * 1024,
            maxDuration: 15 * 60,
            maxResponseBytes: 1024 * 1024,
            timeout: 10 * 60
        )
    }

    enum Error: Swift.Error, Equatable {
        case audioTooLarge
        case busy
        case helperFailed
        case invalidDuration
        case invalidResponse
        case responseTooLarge
        case runtimeMissing
        case timedOut
    }

    private let executableURL: URL
    private let modelURL: URL
    private let vadModelURL: URL
    private let operationRootURL: URL
    private let environment: [String: String]
    private let limits: Limits
    private var isActive = false

    init(
        executableURL: URL,
        modelURL: URL,
        vadModelURL: URL,
        operationRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-inference", isDirectory: true),
        environment: [String: String] = [:],
        limits: Limits = .production
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.vadModelURL = vadModelURL
        self.operationRootURL = operationRootURL
        self.environment = environment
        self.limits = limits
    }

    func transcribe(
        audioURL: URL,
        declaredDuration: TimeInterval,
        language: String
    ) async throws -> String {
        guard !isActive else { throw Error.busy }
        isActive = true
        defer { isActive = false }

        guard declaredDuration.isFinite,
              declaredDuration > 0,
              declaredDuration <= limits.maxDuration else {
            throw Error.invalidDuration
        }
        let values = try audioURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize else {
            throw Error.helperFailed
        }
        guard fileSize <= limits.maxAudioBytes else { throw Error.audioTooLarge }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: vadModelURL.path) else {
            throw Error.runtimeMissing
        }

        let operationURL = operationRootURL.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: operationURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: operationURL) }
        let outputBaseURL = operationURL.appendingPathComponent("transcript")
        let outputURL = outputBaseURL.appendingPathExtension("txt")

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--model", modelURL.path,
            "--file", audioURL.standardizedFileURL.path,
            "--language", language,
            "--duration", String(Int((declaredDuration * 1_000).rounded(.up))),
            "--vad",
            "--vad-model", vadModelURL.path,
            "--no-timestamps",
            "--no-prints",
            "--output-txt",
            "--output-file", outputBaseURL.path,
        ]
        process.currentDirectoryURL = operationURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
            override
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        do {
            try await waitForExit(process)
        } catch {
            terminate(process)
            throw error
        }
        guard process.terminationStatus == 0 else { throw Error.helperFailed }

        let responseValues = try outputURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard responseValues.isRegularFile == true, let responseSize = responseValues.fileSize else {
            throw Error.invalidResponse
        }
        guard responseSize <= limits.maxResponseBytes else { throw Error.responseTooLarge }
        let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else { throw Error.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForExit(_ process: Process) async throws {
        let deadline = Date().addingTimeInterval(limits.timeout)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw Error.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }
}
