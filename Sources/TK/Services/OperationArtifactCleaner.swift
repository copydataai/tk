import Darwin
import Foundation

struct OperationArtifacts: Equatable, Sendable {
    let operationID: UUID
    let directoryURL: URL
    let recordingURL: URL
    let wavURL: URL
}

struct OperationArtifactCleanupReport: Equatable, Sendable {
    var removedOperationIDs: [UUID] = []
    var retainedFreshCount = 0
    var retainedLiveCount = 0
    var failedCount = 0
}

struct OperationArtifactCleaner: Sendable {
    static let defaultRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("tk-audio", isDirectory: true)
    static let defaultStaleAge: TimeInterval = 24 * 60 * 60

    private struct OwnerMarker: Codable {
        let operationID: UUID
        let process: ResidentProcessRecord
    }

    private let rootURL: URL
    private let staleAge: TimeInterval
    private let now: @Sendable () -> Date
    private let processIsLive: @Sendable (ResidentProcessRecord) -> Bool

    init(
        rootURL: URL = Self.defaultRootURL,
        staleAge: TimeInterval = Self.defaultStaleAge,
        now: @escaping @Sendable () -> Date = { Date() },
        processIsLive: @escaping @Sendable (ResidentProcessRecord) -> Bool = {
            Self.isLiveVerified($0)
        }
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.staleAge = staleAge
        self.now = now
        self.processIsLive = processIsLive
    }

    func createOperation(operationID: UUID) throws -> OperationArtifacts {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let directoryURL = rootURL.appendingPathComponent(operationID.uuidString, isDirectory: true)
        guard isDirectChild(directoryURL) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let marker = OwnerMarker(
                operationID: operationID,
                process: ResidentProcessRecord(
                    processIdentifier: ProcessInfo.processInfo.processIdentifier,
                    executableURL: executableURL
                )
            )
            try JSONEncoder().encode(marker).write(
                to: directoryURL.appendingPathComponent("owner.json"),
                options: .atomic
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
        return OperationArtifacts(
            operationID: operationID,
            directoryURL: directoryURL,
            recordingURL: directoryURL.appendingPathComponent("recording.caf"),
            wavURL: directoryURL.appendingPathComponent("speech.wav")
        )
    }

    func removeOperation(operationID: UUID) {
        let directoryURL = rootURL.appendingPathComponent(operationID.uuidString, isDirectory: true)
        guard isDirectChild(directoryURL), ownedMarker(at: directoryURL)?.operationID == operationID else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func cleanupStale() -> OperationArtifactCleanupReport {
        var report = OperationArtifactCleanupReport()
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return report }

        for directoryURL in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard isDirectChild(directoryURL),
                  let values = try? directoryURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
                  ),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let marker = ownedMarker(at: directoryURL),
                  directoryURL.lastPathComponent == marker.operationID.uuidString else {
                continue
            }
            guard let modifiedAt = values.contentModificationDate,
                  now().timeIntervalSince(modifiedAt) > staleAge else {
                report.retainedFreshCount += 1
                continue
            }
            guard !processIsLive(marker.process) else {
                report.retainedLiveCount += 1
                continue
            }
            do {
                try FileManager.default.removeItem(at: directoryURL)
                report.removedOperationIDs.append(marker.operationID)
            } catch {
                report.failedCount += 1
            }
        }
        return report
    }

    private func ownedMarker(at directoryURL: URL) -> OwnerMarker? {
        let markerURL = directoryURL.appendingPathComponent("owner.json")
        guard isDirectChild(directoryURL),
              let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(OwnerMarker.self, from: data) else {
            return nil
        }
        return marker
    }

    private func isDirectChild(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == rootURL
    }

    private static func isLiveVerified(_ record: ResidentProcessRecord) -> Bool {
        guard record.processIdentifier > 1 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(record.processIdentifier, &path, UInt32(path.count)) > 0 else { return false }
        return URL(fileURLWithPath: String(cString: path)).standardizedFileURL.path
            == record.executablePath
    }
}
