import Foundation

enum PendingDictationStoreError: LocalizedError {
    case corruptData(URL)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .corruptData:
            "The pending dictation file is corrupt. It was preserved for diagnosis."
        case .fileSystem(let message):
            "Pending dictation storage error: \(message)"
        }
    }
}

final class PendingDictationStore {
    private let fileURL: URL

    static func applicationSupport() throws -> PendingDictationStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return PendingDictationStore(
            fileURL: directory
                .appendingPathComponent("tk", isDirectory: true)
                .appendingPathComponent("pending-dictation.json")
        )
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> PendingDictation? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(PendingDictation.self, from: data)
        } catch is DecodingError {
            throw PendingDictationStoreError.corruptData(fileURL)
        } catch {
            throw PendingDictationStoreError.fileSystem(error.localizedDescription)
        }
    }

    func save(_ pending: PendingDictation) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Self.encoder.encode(pending)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw PendingDictationStoreError.fileSystem(error.localizedDescription)
        }
    }

    func discard() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw PendingDictationStoreError.fileSystem(error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
