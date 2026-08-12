import Darwin
import Foundation

enum MemoryPressureLevel: String, Codable, Sendable { case normal, warning, critical }

struct InferenceLiveProbes: Sendable {
    let availableMemoryBytes: @Sendable () throws -> UInt64
    let memoryPressure: @Sendable () throws -> MemoryPressureLevel
    let helperAvailable: @Sendable (URL) throws -> Bool
    let activeOperations: @Sendable () throws -> Int

    static let production = Self(
        availableMemoryBytes: {
            var pageSize: vm_size_t = 0
            guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
                throw InferenceProbeError.indeterminate
            }
            var statistics = vm_statistics64()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
            )
            let result = withUnsafeMutablePointer(to: &statistics) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { throw InferenceProbeError.indeterminate }
            let pages = UInt64(statistics.free_count)
                + UInt64(statistics.inactive_count)
                + UInt64(statistics.speculative_count)
                + UInt64(statistics.purgeable_count)
            return pages * UInt64(pageSize)
        },
        memoryPressure: {
            switch ProcessInfo.processInfo.thermalState {
            case .critical, .serious:
                return .critical
            case .fair:
                return .warning
            case .nominal:
                break
            @unknown default:
                throw InferenceProbeError.indeterminate
            }
            var level: Int32 = 0
            var size = MemoryLayout<Int32>.size
            guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
                throw InferenceProbeError.indeterminate
            }
            switch level {
            case 1: return .normal
            case 2: return .warning
            case 4: return .critical
            default: throw InferenceProbeError.indeterminate
            }
        },
        helperAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) },
        activeOperations: { InferenceOperationOwnership.activeCount }
    )
}

enum InferenceProbeError: Error { case indeterminate }

final class InferenceOperationOwnership: @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0

    static var activeCount: Int { lock.withLock { count } }

    static func acquire() -> Bool {
        lock.withLock {
            guard count == 0 else { return false }
            count += 1
            return true
        }
    }

    static func release() {
        lock.withLock { count = max(0, count - 1) }
    }
}

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
