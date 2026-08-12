@preconcurrency import AVFoundation
import Foundation

struct CaptureSetup: @unchecked Sendable {
    let session: AVCaptureSession
    let output: AVCaptureAudioFileOutput
    let deviceID: String
    let deviceName: String
}

enum MicrophoneCapture {
    static func prepare() throws -> CaptureSetup {
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

        var lastError: Error?
        var fallbackDevice: AVCaptureDevice?
        if let savedDevice = devices.first(where: { $0.uniqueID == savedID }) {
            do {
                return try configure(savedDevice)
            } catch {
                lastError = error
            }
        }

        for device in devices {
            do {
                let result = try probe(device)
                if result.works {
                    return try configure(device)
                }
                if fallbackDevice == nil && result.hasSamples {
                    fallbackDevice = device
                }
            } catch {
                lastError = error
            }
        }

        if let fallbackDevice {
            do {
                return try configure(fallbackDevice)
            } catch {
                lastError = error
            }
        }

        if let firstDevice = devices.first {
            do {
                return try configure(firstDevice)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MicrophoneError.noWorkingInput
    }

    static func devicePriority(_ deviceID: String, savedID: String?, defaultID: String?) -> Int {
        if deviceID == savedID { return 0 }
        if deviceID == defaultID { return 1 }
        return 2
    }

    static func isWorkingInput(level: Float) -> Bool {
        level > -120
    }

    static func recordingSucceeded(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return true }
        return error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
    }

    static func convertToWhisperWAV(_ recordingURL: URL, outputURL: URL) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            recordingURL.path,
            outputURL.path,
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MicrophoneError.conversionFailed(
                message.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "afconvert exited with status \(process.terminationStatus)"
            )
        }
    }

    private static func configure(_ device: AVCaptureDevice) throws -> CaptureSetup {
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
    }

    private struct ProbeResult {
        let works: Bool
        let hasSamples: Bool
    }

    private static func probe(_ device: AVCaptureDevice) throws -> ProbeResult {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        let sink = AudioProbeSink()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw MicrophoneError.configurationFailed
        }
        output.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "tk.microphone-probe"))
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
        let hasSamples = sink.receivedSamples
        return ProbeResult(
            works: hasSamples && isWorkingInput(level: level),
            hasSamples: hasSamples
        )
    }
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

enum MicrophoneError: LocalizedError {
    case configurationFailed
    case conversionFailed(String)
    case noWorkingInput

    var errorDescription: String? {
        switch self {
        case .configurationFailed:
            "The microphone could not be configured"
        case let .conversionFailed(message):
            message
        case .noWorkingInput:
            "No connected microphone is producing audio"
        }
    }
}
