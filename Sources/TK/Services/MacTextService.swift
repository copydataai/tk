import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox

enum MacTextError: LocalizedError {
    case accessibilityRequired
    case noFocusedControl
    case noSelectedText
    case eventCreationFailed
    case speechFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Enable tk in System Settings → Privacy & Security → Accessibility"
        case .noFocusedControl:
            "No editable text field is focused"
        case .noSelectedText:
            "Select some text first"
        case .eventCreationFailed:
            "macOS could not send the keyboard event"
        case .speechFailed(let message):
            message
        }
    }
}

@MainActor
final class MacTextService {
    static let defaultVoice = "en-US-heart"

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }
    static var availableVoices: [String] {
        guard let directory = Bundle.main.resourceURL?
            .appendingPathComponent("kokoro/voices", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else {
            return [defaultVoice]
        }
        return files
            .filter { $0.pathExtension == "bin" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private var speechProcess: Process?
    private var audioPlayer: AVQueuePlayer?
    private var speechURLs: [URL] = []

    init() {
        let check = Self.speechChunks(String(repeating: "word ", count: 100))
        assert(check.count == 2 && check.allSatisfy { $0.count <= 350 })
    }

    func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func insert(_ text: String) async throws {
        guard hasAccessibilityPermission else { throw MacTextError.accessibilityRequired }
        guard !text.isEmpty else { return }

        if let focusedElement,
           AXUIElementSetAttributeValue(
               focusedElement,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success {
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try postCommandKey(UInt16(kVK_ANSI_V))
        // ponytail: fixed delay keeps the clipboard intact; add per-app confirmation if slow apps miss pastes.
        try await Task.sleep(for: .milliseconds(150))
        snapshot.restore(to: pasteboard)
    }

    func selectedText() async throws -> String {
        guard hasAccessibilityPermission else { throw MacTextError.accessibilityRequired }

        if let focusedElement {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &value
            ) == .success,
               let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let changeCount = pasteboard.changeCount
        try postCommandKey(UInt16(kVK_ANSI_C))
        try await Task.sleep(for: .milliseconds(150))
        defer { snapshot.restore(to: pasteboard) }

        guard pasteboard.changeCount != changeCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacTextError.noSelectedText
        }
        return text
    }

    func speak(
        _ text: String,
        voiceIdentifier: String,
        rate: Float,
        volume: Float
    ) async throws {
        stopSpeaking()

        guard let resources = Bundle.main.resourceURL else {
            throw MacTextError.speechFailed("Kokoro runtime is missing; rebuild tk")
        }
        let runtime = resources.appendingPathComponent("kokoro/babylon")
        let modelDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/models", isDirectory: true)
        for chunk in Self.speechChunks(text) {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("tk-speech-\(UUID().uuidString).wav")
            speechURLs.append(output)
            let process = Process()
            let errors = Pipe()
            process.executableURL = runtime
            process.arguments = [
                "--phonemizer-model", resources.appendingPathComponent("kokoro/models/open-phonemizer.onnx").path,
                "--dictionary", resources.appendingPathComponent("kokoro/data/dictionary.json").path,
                "--kokoro-model", modelDirectory.appendingPathComponent("kokoro-v1.0-fp32.onnx").path,
                "--kokoro-voices", resources.appendingPathComponent("kokoro/voices").path,
                "tts",
                "--voice", voiceIdentifier,
                "--speed", String(min(max(rate, 0.5), 2)),
                chunk,
                "-o", output.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            speechProcess = process

            let status: Int32
            do {
                status = try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { process in
                        continuation.resume(returning: process.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                stopSpeaking()
                throw MacTextError.speechFailed("Could not start Kokoro: \(error.localizedDescription)")
            }

            guard speechProcess === process else { throw CancellationError() }
            speechProcess = nil
            guard status == 0,
                  (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 44 else {
                let detail = String(
                    data: errors.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                stopSpeaking()
                if let detail, !detail.isEmpty {
                    throw MacTextError.speechFailed(detail)
                }
                throw MacTextError.speechFailed("Kokoro could not generate speech")
            }
        }

        let player = AVQueuePlayer(items: speechURLs.map(AVPlayerItem.init(url:)))
        player.volume = min(max(volume, 0), 1)
        player.play()
        audioPlayer = player
    }

    func stopSpeaking() {
        if speechProcess?.isRunning == true {
            speechProcess?.terminate()
        }
        speechProcess = nil
        audioPlayer?.pause()
        audioPlayer?.removeAllItems()
        audioPlayer = nil
        for speechURL in speechURLs {
            try? FileManager.default.removeItem(at: speechURL)
        }
        speechURLs.removeAll()
    }

    private static func speechChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var chunk = ""

        for wordSlice in text.split(whereSeparator: \.isWhitespace) {
            var word = String(wordSlice)
            while word.count > 350 {
                if !chunk.isEmpty {
                    chunks.append(chunk)
                    chunk = ""
                }
                let end = word.index(word.startIndex, offsetBy: 350)
                chunks.append(String(word[..<end]))
                word = String(word[end...])
            }
            guard !word.isEmpty else { continue }
            if chunk.isEmpty {
                chunk = word
            } else if chunk.count + word.count < 350 {
                chunk += " \(word)"
            } else {
                chunks.append(chunk)
                chunk = word
            }
        }
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
        return chunks
    }

    private var focusedElement: AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func postCommandKey(_ keyCode: CGKeyCode) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw MacTextError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
