import Foundation

struct DiagnosticsReport: Codable, Equatable, Sendable {
    let appVersion: String
    let macOSVersion: String
    let architecture: String
    let profileAvailability: [String: DiagnosticsProfileAvailability]
    let accessibilityPermissionGranted: Bool
    let microphonePermissionGranted: Bool
    let status: DiagnosticsStatus
    let performanceMeasurements: [String: Double]
    let performanceBudgetsPassed: [String: Bool]

    func exportedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

enum DiagnosticsProfileAvailability: String, Codable, Equatable, Sendable {
    case available
    case checking
    case missing
    case downloading
    case interrupted
    case failed

    init(_ availability: ProfileAvailability) {
        switch availability {
        case .available: self = .available
        case .checking: self = .checking
        case .missing: self = .missing
        case .downloading: self = .downloading
        case .interrupted: self = .interrupted
        case .failed: self = .failed
        }
    }
}

enum DiagnosticsStatus: String, Codable, Equatable, Sendable {
    case ready
    case recording
    case transcribing
    case reading
    case downloading
    case unavailable
    case error
    case unknown

    init(sanitizing status: String) {
        let normalized = status.lowercased()
        if normalized == "ready" || normalized.contains("press the shortcut") {
            self = .ready
        } else if normalized.contains("record") {
            self = .recording
        } else if normalized.contains("transcrib") {
            self = .transcribing
        } else if normalized.contains("read") || normalized.contains("speech") || normalized.contains("voice") {
            self = .reading
        } else if normalized.contains("download") {
            self = .downloading
        } else if normalized.contains("unavailable") || normalized.contains("missing") || normalized.contains("permission") {
            self = .unavailable
        } else if normalized.contains("error") || normalized.contains("failed") || normalized.contains("could not") {
            self = .error
        } else {
            self = .unknown
        }
    }
}
