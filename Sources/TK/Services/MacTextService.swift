import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import Darwin

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
final class MacTextService: NSObject {
    static let defaultVoice = "en-US-heart"

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }
    static let availableVoices: [String] = {
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
    }()

    nonisolated private static var babylonPIDURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("tk/babylon-server.pid")
    }

    private var babylonProcess: Process?
    private var babylonPort: Int?
    private var activeProfileID: String?
    private var speechRequest: Task<(Data, URLResponse), Error>?
    private var speechID: UUID?
    private var audioPlayer: AVQueuePlayer?
    private var speechURLs: [URL] = []
    private var insertionTarget: MacAccessibility.InsertionTarget?
    private var pasteboardOperationInProgress = false
    private var pasteboardWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let check = Self.speechChunks(String(repeating: "word ", count: 100))
        assert(check.count == 2 && check.allSatisfy { $0.count <= 350 })
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        speechRequest?.cancel()
        if let babylonProcess, babylonProcess.isRunning {
            kill(babylonProcess.processIdentifier, SIGKILL)
        }
        try? FileManager.default.removeItem(at: Self.babylonPIDURL)
        for speechURL in speechURLs {
            try? FileManager.default.removeItem(at: speechURL)
        }
    }

    func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func rememberInsertionTarget() {
        insertionTarget = MacAccessibility.insertionTarget(from: focusedElement)
    }

    func insert(_ text: String) async -> InsertionReceipt {
        guard hasAccessibilityPermission else {
            return .failedRecoverable(.accessibilityRequired)
        }
        guard !text.isEmpty else { return .verified }

        let target = insertionTarget ?? MacAccessibility.insertionTarget(from: focusedElement)
        insertionTarget = nil
        guard let target else { return .failedRecoverable(.noFocusedControl) }
        guard target.supportsSelectedTextWrite else {
            return .failedRecoverable(.unsupportedControl)
        }
        guard let current = MacAccessibility.insertionTarget(from: focusedElement),
              target.fingerprint.corresponds(to: current.fingerprint) else {
            return .targetMismatch
        }

        let writeSucceeded = AXUIElementSetAttributeValue(
               target.element,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success
        if writeSucceeded {
            let readback = MacAccessibility.selectedText(of: target.element)
            return .axWriteResult(
                writeSucceeded: true,
                readbackMatches: readback.map { $0 == text }
            )
        }

        try? await restoreFocus(to: target.element)

        await acquirePasteboardAccess()
        defer { releasePasteboardAccess() }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedTextChangeCount = pasteboard.changeCount
        guard postCommandKeyIfPossible(UInt16(kVK_ANSI_V)) else {
            return .copyOnly
        }
        // ponytail: fixed delay keeps the clipboard intact; add per-app confirmation if slow apps miss pastes.
        try? await Task.sleep(for: .milliseconds(150))
        snapshot.restore(to: pasteboard, ifChangeCountIs: insertedTextChangeCount)
        return .attempted
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

        await acquirePasteboardAccess()
        defer { releasePasteboardAccess() }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: .tkCopySentinel)
        try postCommandKey(UInt16(kVK_ANSI_C))
        try await Task.sleep(for: .milliseconds(150))
        let copiedTextChangeCount = pasteboard.changeCount
        defer {
            snapshot.restore(to: pasteboard, ifChangeCountIs: copiedTextChangeCount)
        }

        guard pasteboard.data(forType: .tkCopySentinel) == nil,
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
        volume: Float,
        artifact: SpeechArtifact
    ) async throws {
        stopSpeaking()
        let speechID = UUID()
        self.speechID = speechID

        guard let resources = Bundle.main.resourceURL else {
            self.speechID = nil
            throw MacTextError.speechFailed("Kokoro runtime is missing; rebuild tk")
        }
        let serverURL: URL
        do {
            serverURL = try await babylonServerURL(
                resources: resources,
                artifact: artifact,
                speechID: speechID
            )
        } catch {
            guard self.speechID == speechID else { throw CancellationError() }
            stopSpeaking()
            if error is CancellationError { throw error }
            throw MacTextError.speechFailed("Could not start Kokoro: \(error.localizedDescription)")
        }

        let player = AVQueuePlayer()
        player.volume = min(max(volume, 0), 1)
        audioPlayer = player

        for chunk in Self.speechChunks(text) {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("tk-speech-\(UUID().uuidString).wav")
            speechURLs.append(output)

            var request = URLRequest(url: serverURL.appendingPathComponent("tts"))
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "text": chunk,
                "engine": "kokoro",
                "voice": voiceIdentifier,
                "speed": min(max(rate, 0.5), 2)
            ])

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await send(request, speechID: speechID)
            } catch {
                guard self.speechID == speechID else { throw CancellationError() }
                stopSpeaking()
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                throw MacTextError.speechFailed("Kokoro request failed: \(error.localizedDescription)")
            }

            guard self.speechID == speechID else { throw CancellationError() }
            guard response.statusCode == 200, data.count > 44 else {
                let detail = (try? JSONSerialization.jsonObject(with: data))
                    .flatMap { $0 as? [String: Any] }?["error"] as? String
                stopSpeaking()
                if let detail, !detail.isEmpty {
                    throw MacTextError.speechFailed(detail)
                }
                throw MacTextError.speechFailed("Kokoro could not generate speech")
            }

            do {
                try data.write(to: output, options: .atomic)
            } catch {
                stopSpeaking()
                throw MacTextError.speechFailed("Could not save Kokoro audio: \(error.localizedDescription)")
            }
            player.insert(AVPlayerItem(url: output), after: nil)
            player.play()
        }

        if self.speechID == speechID {
            self.speechID = nil
        }
    }

    func stopSpeaking() {
        speechID = nil
        speechRequest?.cancel()
        speechRequest = nil
        audioPlayer?.pause()
        audioPlayer?.removeAllItems()
        audioPlayer = nil
        for speechURL in speechURLs {
            try? FileManager.default.removeItem(at: speechURL)
        }
        speechURLs.removeAll()
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        stopSpeaking()
        if let babylonProcess, babylonProcess.isRunning {
            kill(babylonProcess.processIdentifier, SIGKILL)
        }
        babylonProcess = nil
        try? FileManager.default.removeItem(at: Self.babylonPIDURL)
    }

    private func babylonServerURL(
        resources: URL,
        artifact: SpeechArtifact,
        speechID: UUID
    ) async throws -> URL {
        if let babylonProcess,
           babylonProcess.isRunning,
           activeProfileID == artifact.profileID,
           let babylonPort {
            return URL(string: "http://127.0.0.1:\(babylonPort)")!
        }

        if babylonProcess != nil {
            stopBabylon()
        } else {
            babylonPort = nil
            activeProfileID = nil
        }
        let executableURL = resources.appendingPathComponent("kokoro/babylon")
        let modelURL = artifact.url
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw MacTextError.speechFailed("The selected reading profile is unavailable")
        }
        ResidentProcessRecord.read(
            from: Self.babylonPIDURL,
            legacyExecutableURL: executableURL
        )?.terminateIfOrphaned()
        try? FileManager.default.removeItem(at: Self.babylonPIDURL)
        var lastError: Error = MacTextError.speechFailed("Kokoro did not become ready")
        for _ in 0..<3 {
            let port = Int.random(in: 49_152...65_535)
            let process = Process()
            process.executableURL = executableURL
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.arguments = [
                "--phonemizer-model", resources.appendingPathComponent("kokoro/models/open-phonemizer.onnx").path,
                "--dictionary", resources.appendingPathComponent("kokoro/data/dictionary.json").path,
                "--kokoro-model", modelURL.path,
                "--kokoro-voices", resources.appendingPathComponent("kokoro/voices").path,
                "serve",
                "--host", "127.0.0.1",
                "--port", String(port)
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                try ResidentProcessRecord(
                    processIdentifier: process.processIdentifier,
                    executableURL: executableURL
                ).write(to: Self.babylonPIDURL)
            } catch {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                lastError = error
                continue
            }
            babylonProcess = process
            babylonPort = port

            let serverURL = URL(string: "http://127.0.0.1:\(port)")!
            var request = URLRequest(url: serverURL.appendingPathComponent("status"))
            request.timeoutInterval = 120
            for _ in 0..<100 {
                guard self.speechID == speechID else { throw CancellationError() }
                guard process.isRunning else {
                    lastError = MacTextError.speechFailed("Kokoro stopped while starting")
                    break
                }
                do {
                    let (_, response) = try await send(request, speechID: speechID)
                    guard response.statusCode == 200 else {
                        throw MacTextError.speechFailed("Kokoro readiness check failed")
                    }
                    activeProfileID = artifact.profileID
                    return serverURL
                } catch {
                    guard self.speechID == speechID else { throw CancellationError() }
                    lastError = error
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            try? FileManager.default.removeItem(at: Self.babylonPIDURL)
            babylonProcess = nil
            babylonPort = nil
            activeProfileID = nil
        }
        throw lastError
    }

    private func stopBabylon() {
        if let babylonProcess, babylonProcess.isRunning {
            kill(babylonProcess.processIdentifier, SIGKILL)
        }
        babylonProcess = nil
        babylonPort = nil
        activeProfileID = nil
        try? FileManager.default.removeItem(at: Self.babylonPIDURL)
    }

    private func send(
        _ request: URLRequest,
        speechID: UUID
    ) async throws -> (Data, HTTPURLResponse) {
        let task = Task { try await URLSession.shared.data(for: request) }
        speechRequest = task
        defer {
            if self.speechID == speechID {
                speechRequest = nil
            }
        }
        let (data, response) = try await task.value
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
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
        MacAccessibility.focusedElement
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

    private func postCommandKeyIfPossible(_ keyCode: CGKeyCode) -> Bool {
        do {
            try postCommandKey(keyCode)
            return true
        } catch {
            return false
        }
    }

    private func restoreFocus(to target: AXUIElement) async throws {
        try await MacAccessibility.restoreFocus(to: target)
    }

    private func acquirePasteboardAccess() async {
        if !pasteboardOperationInProgress {
            pasteboardOperationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            pasteboardWaiters.append(continuation)
        }
    }

    private func releasePasteboardAccess() {
        guard !pasteboardWaiters.isEmpty else {
            pasteboardOperationInProgress = false
            return
        }
        pasteboardWaiters.removeFirst().resume()
    }
}
