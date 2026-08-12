import Foundation

enum MemoryPressureLevel: String, Codable, Sendable { case normal, warning, critical }

struct InferenceProfileEstimate: Equatable, Sendable {
    let profileID: String
    let requiredMemoryBytes: UInt64
    let device: String
}

struct InferencePreflight: Equatable, Sendable {
    let duration: TimeInterval
    let audioBytes: Int
    let audioFormat: String
    let availableMemoryBytes: UInt64
    let memoryPressure: MemoryPressureLevel
    let helperAvailable: Bool
    let profile: InferenceProfileEstimate
    let activeOperations: Int
}

enum InferenceAdmissionOutcome: Error, Equatable, Sendable {
    case admitted
    case invalidDuration
    case unsupportedAudioFormat
    case audioTooLarge
    case memoryUnavailable
    case memoryPressure
    case helperUnavailable
    case selectedProfileUnavailable(String)
    case busy
}

struct InferenceAdmissionPolicy: Equatable, Sendable {
    let maxDuration: TimeInterval
    let maxAudioBytes: Int
    let allowedFormats: Set<String>
    let maxConcurrency: Int

    func evaluate(_ input: InferencePreflight) -> InferenceAdmissionOutcome {
        guard input.duration.isFinite, input.duration > 0, input.duration <= maxDuration else {
            return .invalidDuration
        }
        guard allowedFormats.contains(input.audioFormat.lowercased()) else {
            return .unsupportedAudioFormat
        }
        guard input.audioBytes >= 0, input.audioBytes <= maxAudioBytes else { return .audioTooLarge }
        guard input.memoryPressure != .critical else { return .memoryPressure }
        guard input.availableMemoryBytes >= input.profile.requiredMemoryBytes else {
            return .selectedProfileUnavailable(input.profile.profileID)
        }
        guard input.helperAvailable else { return .helperUnavailable }
        guard input.activeOperations < maxConcurrency else { return .busy }
        return .admitted
    }
}

struct InferencePerformanceReceipt: Codable, Equatable, Sendable {
    enum Termination: String, Codable, Sendable { case exited, timedOut, cancelled, signalled, launchFailed }

    let operationID: UUID
    let profileID: String
    let coldStart: Bool
    let startupMilliseconds: Int
    let inferenceMilliseconds: Int
    let peakMemoryBytes: UInt64?
    let termination: Termination
    let cleanupSucceeded: Bool
    let responseBytes: Int
}

struct HardwarePerformanceThreshold: Codable, Equatable, Sendable {
    let hardwareIdentifier: String
    let profileID: String
    let maximumInferenceMilliseconds: Int
    let maximumPeakMemoryBytes: UInt64
}
