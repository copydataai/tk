import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let dictation = DictationService()

    private let hotKeys = GlobalHotKeyService()
    private let macText = MacTextService()
    private var transcriptStore: TranscriptStore?
    private var transcriptStoreError: String?

    var statusMessage = "Ready"
    var accessibilityGranted = false
    var transcripts: [TranscriptRecord] = []

    var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "kokoroVoiceIdentifier") }
    }

    var speechRate: Double {
        didSet { UserDefaults.standard.set(speechRate, forKey: "kokoroSpeechRate") }
    }

    var speechVolume: Double {
        didSet { UserDefaults.standard.set(speechVolume, forKey: "speechVolume") }
    }

    var transcriptionLanguageCode: String? {
        didSet { UserDefaults.standard.set(transcriptionLanguageCode, forKey: "transcriptionLanguageCode") }
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
        transcriptionLanguageCode = UserDefaults.standard.string(
            forKey: "transcriptionLanguageCode"
        )
        dictationShortcut = Self.savedShortcut(
            key: "dictationShortcut",
            fallback: .controlOptionSpace
        )
        readShortcut = Self.savedShortcut(
            key: "readShortcut",
            fallback: .controlOptionR
        )

        assert(Set(HotKeyOption.dictationChoices).isDisjoint(with: HotKeyOption.readingChoices))

        do {
            transcriptStore = try TranscriptStore.applicationSupport()
            transcripts = try transcriptStore?.recent() ?? []
        } catch {
            transcriptStoreError = error.localizedDescription
        }

        dictation.onTranscriptReady = { [weak self] text in
            Task { @MainActor in
                await self?.saveAndInsert(text)
            }
        }
        hotKeys.onDictation = { [weak self] in self?.toggleDictation() }
        hotKeys.onReadSelection = { [weak self] in self?.readSelection() }
        hotKeys.start()
        configureHotKeys()
        refreshPermissions()
        if let transcriptStoreError {
            statusMessage = "History unavailable: \(transcriptStoreError)"
        }
    }

    func toggleDictation() {
        guard accessibilityGranted else {
            requestAccessibility()
            return
        }
        if !dictation.isRecording && !dictation.isTranscribing {
            macText.rememberInsertionTarget()
        }
        dictation.toggle(language: transcriptionLanguageCode)
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

    func previewVoice(_ identifier: String) {
        Task {
            do {
                statusMessage = "Generating voice preview"
                try await macText.speak(
                    Self.previewText(for: identifier),
                    voiceIdentifier: identifier,
                    rate: Float(speechRate),
                    volume: Float(speechVolume)
                )
                statusMessage = "Playing voice preview"
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

    private func saveAndInsert(_ text: String) async {
        do {
            guard let transcriptStore else {
                throw TranscriptStoreError.sqlite(
                    transcriptStoreError ?? "The database is unavailable."
                )
            }
            transcripts.insert(try transcriptStore.insert(text), at: 0)
            transcriptStoreError = nil
            if transcripts.count > 50 {
                transcripts.removeLast()
            }
        } catch {
            transcriptStoreError = error.localizedDescription
        }

        do {
            try await macText.insert(text)
            statusMessage = transcriptStoreError.map {
                "Inserted, but history could not be saved: \($0)"
            } ?? "Inserted transcription"
        } catch {
            statusMessage = transcriptStoreError.map {
                "History could not be saved: \($0). Insertion also failed: \(error.localizedDescription)"
            } ?? error.localizedDescription
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

    private static func previewText(for voice: String) -> String {
        switch String(voice.prefix(2)) {
        case "de": "Hallo, so klingt meine Stimme."
        case "el": "Γεια σας, έτσι ακούγεται η φωνή μου."
        case "fr": "Bonjour, voici un aperçu de ma voix."
        case "it": "Ciao, ecco un'anteprima della mia voce."
        case "ja": "こんにちは、私の声はこのように聞こえます。"
        case "pt": "Olá, esta é uma prévia da minha voz."
        case "zh": "你好，这是我的声音预览。"
        default: "Hi, this is a preview of my voice."
        }
    }
}
