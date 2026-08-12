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
        case processGroupUnavailable
    }

    private let executableURL: URL
    private let modelURL: URL
    private let vadModelURL: URL
    private let operationRootURL: URL
    private let environment: [String: String]
    private let limits: Limits
    private var isActive = false
    private(set) var lastReceipt: InferencePerformanceReceipt?

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
        language: String,
        operationID: UUID = UUID(),
        profileID: String = "unknown",
        coldStart: Bool = true
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
        let processGroupURL = operationURL.appendingPathComponent("process-group")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        let helperArguments = [
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
        process.arguments = [
            "-MPOSIX",
            "-e",
            "my $f=shift; my $p=fork(); defined $p or die qq(fork failed); if($p){waitpid($p,0); exit($?>>8)} POSIX::setsid()>=0 or die qq(setsid failed); open(my $h,qq(>),$f) or die qq(handshake failed); print $h $$; close $h; exec {$ARGV[0]} @ARGV or die qq(exec failed)",
            processGroupURL.path,
            executableURL.path,
        ] + helperArguments
        process.currentDirectoryURL = operationURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
            override
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let startedAt = ContinuousClock.now
        try process.run()
        let startupMilliseconds = Int(startedAt.duration(to: .now).inferenceMilliseconds.rounded())
        var processGroup: pid_t?
        for _ in 0..<40 where process.isRunning && processGroup == nil {
            if let value = try? String(contentsOf: processGroupURL, encoding: .utf8),
               let identifier = pid_t(value) {
                processGroup = identifier
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard process.isRunning,
              let processGroup,
              getpgid(processGroup) == processGroup else {
            process.terminate()
            process.waitUntilExit()
            throw Error.processGroupUnavailable
        }
        let inferenceStartedAt = ContinuousClock.now
        do {
            try await waitForExit(process)
        } catch {
            terminate(process, processGroup: processGroup)
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
        lastReceipt = InferencePerformanceReceipt(
            operationID: operationID,
            profileID: profileID,
            coldStart: coldStart,
            startupMilliseconds: startupMilliseconds,
            inferenceMilliseconds: Int(inferenceStartedAt.duration(to: .now).inferenceMilliseconds.rounded()),
            peakMemoryBytes: nil,
            termination: .exited,
            cleanupSucceeded: true,
            responseBytes: data.count
        )
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

    private func terminate(_ process: Process, processGroup: pid_t) {
        guard process.isRunning else { return }
        kill(-processGroup, SIGKILL)
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }
}

private extension Duration {
    var inferenceMilliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
