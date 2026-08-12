import Foundation

enum EvidenceKind: String, Codable, Sendable { case physical, simulated }
enum QualificationStatus: String, Codable, Sendable { case pass = "Pass", fail = "Fail", blocked = "Blocked", notRun = "Not run" }

struct ContinuityEvidenceRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let rowID: String
    let kind: EvidenceKind
    let appVersion: String
    let appBuild: String
    let artifactName: String
    let artifactSHA256: String
    let macOSBuild: String
    let hardwareIdentifier: String
    let inputRoute: String
    let inputDeviceUID: String
    let sampleRate: Double
    let operationID: UUID
    let interruptionPhase: String
    let notificationsObserved: [String]
    let outcome: QualificationStatus
    let audioDisposition: String
    let helperDisposition: String
    let testerAssertion: String
    let recordedAt: Date
    let expiresAt: Date
}

struct ContinuityMatrixRow: Codable, Equatable, Sendable {
    let id: String
    let expectedAppVersion: String
    let expectedArtifactSHA256: String
    let expectedMacOSBuild: String
    let expectedHardwareIdentifier: String
    let expectedInputDeviceUID: String
}

enum ContinuityEvidenceError: Error, Equatable {
    case unknownOrAmbiguousRow
    case staleArtifact
    case staleSystem
    case staleDevice
    case missingObservation
    case simulatedCannotPass
    case generalizedEvidence
    case unsupportedSchema
    case staleRecord
}

struct ContinuityEvidenceValidator {
    func validate(_ record: ContinuityEvidenceRecord, rows: [ContinuityMatrixRow]) throws -> ContinuityMatrixRow {
        guard record.schemaVersion == ContinuityEvidenceRecord.schemaVersion else {
            throw ContinuityEvidenceError.unsupportedSchema
        }
        guard record.recordedAt <= Date().addingTimeInterval(300),
              record.expiresAt >= Date(),
              record.expiresAt.timeIntervalSince(record.recordedAt) <= 30 * 24 * 60 * 60 + 60 else {
            throw ContinuityEvidenceError.staleRecord
        }
        let matches = rows.filter { $0.id == record.rowID }
        guard matches.count == 1, let row = matches.first else { throw ContinuityEvidenceError.unknownOrAmbiguousRow }
        guard record.appVersion == row.expectedAppVersion,
              record.artifactSHA256 == row.expectedArtifactSHA256 else { throw ContinuityEvidenceError.staleArtifact }
        guard record.macOSBuild == row.expectedMacOSBuild,
              record.hardwareIdentifier == row.expectedHardwareIdentifier else { throw ContinuityEvidenceError.staleSystem }
        guard record.inputDeviceUID == row.expectedInputDeviceUID else { throw ContinuityEvidenceError.staleDevice }
        guard !record.notificationsObserved.isEmpty,
              !record.testerAssertion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContinuityEvidenceError.missingObservation
        }
        guard record.kind == .physical || record.outcome != .pass else { throw ContinuityEvidenceError.simulatedCannotPass }
        guard !record.rowID.contains(","), !record.inputDeviceUID.contains("*") else {
            throw ContinuityEvidenceError.generalizedEvidence
        }
        return row
    }
}

struct ContinuityEvidenceAggregator {
    func statuses(rows: [ContinuityMatrixRow], records: [ContinuityEvidenceRecord]) -> [String: QualificationStatus] {
        var result = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, QualificationStatus.notRun) })
        let validator = ContinuityEvidenceValidator()
        for record in records where record.kind == .physical {
            if let row = try? validator.validate(record, rows: rows) { result[row.id] = record.outcome }
        }
        return result
    }
}
