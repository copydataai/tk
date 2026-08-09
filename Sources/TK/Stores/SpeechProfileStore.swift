import CryptoKit
import Darwin
import Foundation
import Observation

enum ProfileAvailability: Equatable {
    case available
    case checking
    case missing
    case downloading
    case interrupted(String)
    case failed(String)

    var canSelect: Bool { self == .available }
}

enum SpeechProfileError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

@MainActor
@Observable
final class SpeechProfileStore {
    static let dictationKey = "selectedDictationProfileID"
    static let readingKey = "selectedReadingProfileID"

    private let defaults: UserDefaults
    private let modelDirectory: URL
    private let resourceDirectory: URL?
    private(set) var selectedDictationID: String
    private(set) var selectedReadingID: String
    private(set) var availability: [String: ProfileAvailability] = [:]
    private(set) var downloadingProfileID: String?
    private(set) var downloadedBytes: Int64 = 0
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var deletePartialOnCancellation = false
    @ObservationIgnored private var verifiedFiles: [String: FileFingerprint] = [:]

    init(
        defaults: UserDefaults = .standard,
        modelDirectory: URL? = nil,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) {
        self.defaults = defaults
        self.modelDirectory = modelDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/models", isDirectory: true)
        self.resourceDirectory = resourceDirectory
        selectedDictationID = Self.savedID(
            forKey: Self.dictationKey,
            defaultID: SpeechProfile.defaultIDs[.dictation]!,
            defaults: defaults
        )
        selectedReadingID = Self.savedID(
            forKey: Self.readingKey,
            defaultID: SpeechProfile.defaultIDs[.reading]!,
            defaults: defaults
        )
        defaults.set(selectedDictationID, forKey: Self.dictationKey)
        defaults.set(selectedReadingID, forKey: Self.readingKey)

        refresh()
        Task { await verifyInstalledProfiles() }
    }

    func profiles(for kind: SpeechProfileKind) -> [SpeechProfile] {
        SpeechProfile.profiles(for: kind)
    }

    func selectedID(for kind: SpeechProfileKind) -> String {
        kind == .dictation ? selectedDictationID : selectedReadingID
    }

    func selectedProfile(for kind: SpeechProfileKind) -> SpeechProfile? {
        SpeechProfile.all.first { $0.id == selectedID(for: kind) }
    }

    func isSelected(_ profile: SpeechProfile) -> Bool {
        selectedID(for: profile.kind) == profile.id
    }

    func hasInstalledArtifact(_ profile: SpeechProfile) -> Bool {
        artifactURL(for: profile) != nil
    }

    func select(_ profile: SpeechProfile) {
        guard availability[profile.id]?.canSelect == true else { return }
        if profile.kind == .dictation {
            selectedDictationID = profile.id
            defaults.set(profile.id, forKey: Self.dictationKey)
        } else {
            selectedReadingID = profile.id
            defaults.set(profile.id, forKey: Self.readingKey)
        }
    }

    func artifact(for kind: SpeechProfileKind) throws -> SpeechArtifact {
        try artifact(forID: selectedID(for: kind))
    }

    func artifact(forID id: String) throws -> SpeechArtifact {
        guard let profile = SpeechProfile.all.first(where: { $0.id == id }) else {
            throw SpeechProfileError.unavailable("The saved profile is not available in this version of tk. Choose another profile in Settings.")
        }
        guard availability[profile.id] == .available, let url = artifactURL(for: profile) else {
            throw SpeechProfileError.unavailable(unavailableMessage(for: profile))
        }
        if !profile.isBundled {
            guard let fingerprint = FileFingerprint(url: url),
                  fingerprint == verifiedFiles[profile.id] else {
                availability[profile.id] = .checking
                Task { await verify(profile) }
                throw SpeechProfileError.unavailable("\(profile.name) changed and is being verified. Try again when verification finishes.")
            }
        }
        return SpeechArtifact(profileID: profile.id, url: url)
    }

    func refresh() {
        for profile in SpeechProfile.all {
            if profile.isBundled {
                availability[profile.id] = artifactURL(for: profile) == nil
                    ? .failed("The bundled profile is missing. Reinstall tk.")
                    : .available
            } else if let url = artifactURL(for: profile), fileSize(url) == profile.byteCount {
                availability[profile.id] = verifiedFiles[profile.id] == nil ? .checking : .available
            } else {
                availability[profile.id] = .missing
                verifiedFiles[profile.id] = nil
            }
        }
    }

    func download(_ profile: SpeechProfile) {
        guard !profile.isBundled, downloadingProfileID == nil else { return }
        downloadingProfileID = profile.id
        downloadedBytes = partialSize(for: profile)
        availability[profile.id] = .downloading
        deletePartialOnCancellation = false
        let directory = modelDirectory
        downloadTask = Task {
            do {
                try await Self.downloadFile(profile, to: directory) { bytes in
                    guard self.downloadingProfileID == profile.id else { return }
                    self.downloadedBytes = bytes
                }
                verifiedFiles[profile.id] = artifactURL(for: profile).flatMap(FileFingerprint.init)
                availability[profile.id] = .available
            } catch {
                if deletePartialOnCancellation || Task.isCancelled {
                    try? FileManager.default.removeItem(at: partialURL(for: profile))
                    availability[profile.id] = .missing
                } else if error is URLError {
                    availability[profile.id] = .interrupted(
                        "The download was interrupted. Retry to continue."
                    )
                } else {
                    availability[profile.id] = .failed(error.localizedDescription)
                }
            }
            guard downloadingProfileID == profile.id else { return }
            downloadingProfileID = nil
            downloadedBytes = 0
            downloadTask = nil
            deletePartialOnCancellation = false
        }
    }

    func cancelDownload() {
        deletePartialOnCancellation = true
        downloadTask?.cancel()
    }

    func remove(_ profile: SpeechProfile) throws {
        guard !profile.isBundled else { return }
        if isSelected(profile),
           let defaultID = SpeechProfile.defaultIDs[profile.kind],
           let bundledDefault = SpeechProfile.all.first(where: { $0.id == defaultID }) {
            select(bundledDefault)
        }
        try? FileManager.default.removeItem(at: partialURL(for: profile))
        if let url = artifactURL(for: profile) {
            try FileManager.default.removeItem(at: url)
        }
        verifiedFiles[profile.id] = nil
        availability[profile.id] = .missing
    }

    func unavailableMessage(for profile: SpeechProfile) -> String {
        switch availability[profile.id] ?? .missing {
        case .available: ""
        case .checking: "\(profile.name) is being verified. Try again when verification finishes."
        case .missing: "\(profile.name) is not downloaded. Open Settings to download it."
        case .downloading: "\(profile.name) is still downloading."
        case .interrupted(let message), .failed(let message): message
        }
    }

    private func verifyInstalledProfiles() async {
        for profile in SpeechProfile.all where !profile.isBundled && artifactURL(for: profile) != nil {
            await verify(profile)
        }
    }

    private func verify(_ profile: SpeechProfile) async {
        guard let url = artifactURL(for: profile), fileSize(url) == profile.byteCount else {
            verifiedFiles[profile.id] = nil
            availability[profile.id] = .missing
            return
        }
        let matches = await Task.detached(priority: .utility) {
            (try? Self.sha256(of: url)) == profile.sha256
        }.value
        guard artifactURL(for: profile) == url else { return }
        if matches {
            verifiedFiles[profile.id] = FileFingerprint(url: url)
            availability[profile.id] = .available
        } else {
            verifiedFiles[profile.id] = nil
            availability[profile.id] = .failed("The downloaded profile could not be verified. Remove it and try again.")
        }
    }

    private func artifactURL(for profile: SpeechProfile) -> URL? {
        if profile.isBundled,
           let bundled = resourceDirectory?.appendingPathComponent("models/\(profile.filename)"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let downloaded = modelDirectory.appendingPathComponent(profile.filename)
        return FileManager.default.fileExists(atPath: downloaded.path) ? downloaded : nil
    }

    private func partialURL(for profile: SpeechProfile) -> URL {
        modelDirectory.appendingPathComponent("\(profile.filename).partial")
    }

    private func partialSize(for profile: SpeechProfile) -> Int64 {
        fileSize(partialURL(for: profile)) ?? 0
    }

    private func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    nonisolated static func savedID(
        forKey key: String,
        defaultID: String,
        defaults: UserDefaults
    ) -> String {
        guard let value = defaults.object(forKey: key) as? String,
              !value.isEmpty,
              value.first?.isLetter == true,
              value.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "." || $0 == "-" }) else {
            return defaultID
        }
        return value
    }

    nonisolated private static func downloadFile(
        _ profile: SpeechProfile,
        to directory: URL,
        progress: @MainActor @Sendable @escaping (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent("\(profile.filename).partial")
        let final = directory.appendingPathComponent(profile.filename)
        var existing = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if existing > profile.byteCount {
            try FileManager.default.removeItem(at: partial)
            existing = 0
        }

        let remaining = profile.byteCount - existing
        if let capacity = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage,
           capacity < remaining {
            let required = ByteCountFormatter.string(fromByteCount: remaining, countStyle: .file)
            throw SpeechProfileError.unavailable(
                "Not enough free storage. \(profile.name) needs \(required) available."
            )
        }

        var didRestart = false
        while existing < profile.byteCount {
            var request = URLRequest(url: profile.downloadURL)
            request.timeoutInterval = 600
            if existing > 0 {
                request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            }
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let validResume = existing == 0 || (
                response.statusCode == 206
                    && response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(existing)-") == true
            )
            if !validResume {
                guard !didRestart else { throw URLError(.badServerResponse) }
                try? FileManager.default.removeItem(at: partial)
                existing = 0
                didRestart = true
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }

            if !FileManager.default.fileExists(atPath: partial.path) {
                FileManager.default.createFile(atPath: partial.path, contents: nil)
            }
            var total = existing
            do {
                let handle = try FileHandle(forWritingTo: partial)
                defer { try? handle.close() }
                try handle.seekToEnd()
                var buffer: [UInt8] = []
                buffer.reserveCapacity(64 * 1024)
                for try await byte in bytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    if buffer.count == 64 * 1024 {
                        try handle.write(contentsOf: Data(buffer))
                        total += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        await progress(total)
                    }
                }
                if !buffer.isEmpty {
                    try handle.write(contentsOf: Data(buffer))
                    total += Int64(buffer.count)
                    await progress(total)
                }
            }
            guard total == profile.byteCount else { throw URLError(.cannotDecodeContentData) }
            existing = total
        }

        guard try sha256(of: partial) == profile.sha256 else {
            try? FileManager.default.removeItem(at: partial)
            throw SpeechProfileError.unavailable("The download could not be verified. Try again.")
        }
        let result = partial.path.withCString { source in
            final.path.withCString { destination in rename(source, destination) }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct FileFingerprint: Equatable {
    let size: Int
    let modificationDate: Date?

    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        self.size = size
        modificationDate = values.contentModificationDate
    }
}
