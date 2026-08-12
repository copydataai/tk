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
        case launchFailed
        case cleanupFailed
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
    private let processExecutableURL: URL
    private let processGroupProgram: String?
    private let removeOperationDirectory: @Sendable (URL) throws -> Void
    private var isActive = false
    private(set) var lastReceipt: InferencePerformanceReceipt?

    init(
        executableURL: URL,
        modelURL: URL,
        vadModelURL: URL,
        operationRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-inference", isDirectory: true),
        environment: [String: String] = [:],
        limits: Limits = .production,
        processExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/perl"),
        processGroupProgram: String? = nil,
        removeOperationDirectory: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        }
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.vadModelURL = vadModelURL
        self.operationRootURL = operationRootURL
        self.environment = environment
        self.limits = limits
        self.processExecutableURL = processExecutableURL
        self.processGroupProgram = processGroupProgram
        self.removeOperationDirectory = removeOperationDirectory
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
        let outputBaseURL = operationURL.appendingPathComponent("transcript")
        let outputURL = outputBaseURL.appendingPathExtension("txt")
        let processGroupURL = operationURL.appendingPathComponent("process-group")

        let process = Process()
        process.executableURL = processExecutableURL
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
        let defaultProcessGroupProgram = "my $f=shift; my $p=fork(); defined $p or die qq(fork failed); if($p){waitpid($p,0); my $s=$?&127; kill($s,$$) if $s; exit($?>>8)} POSIX::setsid()>=0 or die qq(setsid failed); open(my $h,qq(>),$f) or die qq(handshake failed); print $h $$; close $h; exec {$ARGV[0]} @ARGV or die qq(exec failed)"
        process.arguments = [
            "-MPOSIX",
            "-e",
            processGroupProgram ?? defaultProcessGroupProgram,
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
        var startupMilliseconds = 0
        var inferenceStartedAt: ContinuousClock.Instant?
        var termination: InferencePerformanceReceipt.Termination = .launchFailed
        var responseBytes = 0
        var primaryError: Swift.Error?
        var processGroup: pid_t?
        var resultText: String?

        do {
            do {
                try process.run()
            } catch {
                throw Error.launchFailed
            }
            startupMilliseconds = Int(startedAt.duration(to: .now).inferenceMilliseconds.rounded())
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
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                throw Error.processGroupUnavailable
            }
            inferenceStartedAt = .now
            do {
                try await waitForExit(process)
            } catch {
                terminate(process, processGroup: processGroup)
                throw error
            }
            guard process.terminationReason == .exit else { throw Error.helperFailed }
            guard process.terminationStatus == 0 else { throw Error.helperFailed }

            guard let responseValues = try? outputURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            ), responseValues.isRegularFile == true, let responseSize = responseValues.fileSize else {
                throw Error.invalidResponse
            }
            responseBytes = responseSize
            guard responseSize <= limits.maxResponseBytes else { throw Error.responseTooLarge }
            let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            guard let text = String(data: data, encoding: .utf8) else { throw Error.invalidResponse }
            responseBytes = data.count
            resultText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            termination = .exited
        } catch {
            primaryError = error
            if error is CancellationError {
                termination = .cancelled
            } else if error as? Error == .timedOut {
                termination = .timedOut
            } else if error as? Error == .launchFailed {
                termination = .launchFailed
            } else if error as? Error == .processGroupUnavailable {
                termination = .processGroupFailed
            } else if error as? Error == .invalidResponse {
                termination = .invalidResponse
            } else if error as? Error == .responseTooLarge {
                termination = .responseTooLarge
            } else if process.terminationReason == .uncaughtSignal {
                termination = .signalled
            } else {
                termination = .nonzeroExit
            }
        }

        var cleanupSucceeded = true
        do {
            try removeOperationDirectory(operationURL)
        } catch {
            cleanupSucceeded = false
            if primaryError == nil {
                primaryError = Error.cleanupFailed
                termination = .cleanupFailed
            }
        }
        let inferenceMilliseconds = inferenceStartedAt.map {
            Int($0.duration(to: .now).inferenceMilliseconds.rounded())
        } ?? 0
        lastReceipt = InferencePerformanceReceipt(
            operationID: operationID,
            profileID: profileID,
            coldStart: coldStart,
            startupMilliseconds: startupMilliseconds,
            inferenceMilliseconds: inferenceMilliseconds,
            peakMemoryBytes: nil,
            termination: termination,
            cleanupSucceeded: cleanupSucceeded,
            responseBytes: responseBytes
        )
        if let primaryError { throw primaryError }
        return resultText ?? ""
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
