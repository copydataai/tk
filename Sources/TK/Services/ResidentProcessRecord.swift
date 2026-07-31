import Darwin
import Foundation

struct ResidentProcessRecord: Codable, Equatable {
    let processIdentifier: pid_t
    let executablePath: String

    init(processIdentifier: pid_t, executableURL: URL) {
        self.processIdentifier = processIdentifier
        executablePath = executableURL.standardizedFileURL.path
    }

    static func read(from url: URL, legacyExecutableURL: URL? = nil) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let record = try? JSONDecoder().decode(Self.self, from: data) {
            return record
        }
        guard let legacyExecutableURL,
              let value = String(data: data, encoding: .utf8),
              let processIdentifier = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return Self(processIdentifier: processIdentifier, executableURL: legacyExecutableURL)
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    func terminateIfOrphaned() {
        guard processIdentifier > 1 else { return }

        var info = proc_bsdinfo()
        let infoSize = MemoryLayout<proc_bsdinfo>.stride
        let bsdInfoFlavor = Int32(3) // PROC_PIDTBSDINFO is unavailable to Swift.
        let bytesRead = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(processIdentifier, bsdInfoFlavor, 0, $0, Int32(infoSize))
        }
        guard bytesRead == infoSize, info.pbi_ppid == 1 else { return }

        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0,
              URL(fileURLWithPath: String(cString: path)).standardizedFileURL.path
                == executablePath else {
            return
        }
        kill(processIdentifier, SIGKILL)
    }
}
