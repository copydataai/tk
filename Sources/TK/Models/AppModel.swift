import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let dictation = DictationService()

    private let hotKeys = GlobalHotKeyService()
    private let macText = MacTextService()

    var statusMessage = "Ready"
    var accessibilityGranted = false

    var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "kokoroVoiceIdentifier") }
    }

    var speechRate: Double {
        didSet { UserDefaults.standard.set(speechRate, forKey: "kokoroSpeechRate") }
    }

    var speechVolume: Double {
        didSet { UserDefaults.standard.set(speechVolume, forKey: "speechVolume") }
    }

    var availableVoices: [String] { MacTextService.availableVoices }

    var dictationShortcut: HotKeyOption {
        didSet {
            UserDefaults.standard.set(dictationShortcut.rawValue, forKey: "dictationShortcut")
            configureHotKeys()
        }
    }

    var readShortcut: HotKeyOption {
        didSet {
            UserDefaults.standard.set(readShortcut.rawValue, forKey: "readShortcut")
            configureHotKeys()
        }
    }

    init() {
        let savedVoice = UserDefaults.standard.string(forKey: "kokoroVoiceIdentifier") ?? ""
        voiceIdentifier = MacTextService.availableVoices.contains(savedVoice)
            ? savedVoice
            : MacTextService.defaultVoice
        speechRate = min(max(Self.savedDouble(
            key: "kokoroSpeechRate",
            fallback: 1
        ), 0.5), 2)
        speechVolume = min(max(Self.savedDouble(key: "speechVolume", fallback: 1), 0), 1)
        dictationShortcut = Self.savedShortcut(
            key: "dictationShortcut",
            fallback: .controlOptionSpace
        )
        readShortcut = Self.savedShortcut(
            key: "readShortcut",
            fallback: .controlOptionR
        )

        assert(Set(HotKeyOption.dictationChoices).isDisjoint(with: HotKeyOption.readingChoices))

        dictation.onTranscriptReady = { [weak self] text in
            Task { @MainActor in
                await self?.insert(text)
            }
        }
        hotKeys.onDictation = { [weak self] in self?.toggleDictation() }
        hotKeys.onReadSelection = { [weak self] in self?.readSelection() }
        hotKeys.start()
        configureHotKeys()
        refreshPermissions()
    }

    func toggleDictation() {
        guard accessibilityGranted else {
            requestAccessibility()
            return
        }
        dictation.toggle()
    }

    func cancelDictation() {
        dictation.cancel()
    }

    func readSelection() {
        guard accessibilityGranted else {
            requestAccessibility()
            return
        }

        Task {
            do {
                let text = try await macText.selectedText()
                statusMessage = "Generating speech"
                try await macText.speak(
                    text,
                    voiceIdentifier: voiceIdentifier,
                    rate: Float(speechRate),
                    volume: Float(speechVolume)
                )
                statusMessage = "Reading selection"
            } catch is CancellationError {
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func stopSpeaking() {
        macText.stopSpeaking()
        statusMessage = "Stopped reading"
    }

    func requestAccessibility() {
        macText.requestAccessibility()
        refreshPermissions()
        statusMessage = accessibilityGranted
            ? "Accessibility is enabled"
            : "Enable tk in System Settings → Privacy & Security → Accessibility"
    }

    func refreshPermissions() {
        accessibilityGranted = macText.hasAccessibilityPermission
    }

    private func configureHotKeys() {
        statusMessage = hotKeys.configure(
            dictation: dictationShortcut,
            reading: readShortcut
        ) ? "Shortcuts ready" : "A shortcut is already used by another app"
    }

    private func insert(_ text: String) async {
        do {
            try await macText.insert(text)
            statusMessage = "Inserted transcription"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func savedShortcut(key: String, fallback: HotKeyOption) -> HotKeyOption {
        guard let rawValue = UserDefaults.standard.string(forKey: key) else { return fallback }
        return HotKeyOption(rawValue: rawValue) ?? fallback
    }

    private static func savedDouble(key: String, fallback: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.double(forKey: key)
    }
}
