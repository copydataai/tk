import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let launchStartedAt = ContinuousClock.now
    let dictation = DictationService()
    let profiles = SpeechProfileStore()

    private let hotKeys = GlobalHotKeyService()
    private let macText = MacTextService()
    private var transcriptStore: TranscriptStore?
    private var transcriptStoreError: String?

    var statusMessage = "Ready"
    var accessibilityGranted = false
    var microphoneGranted = false
    var transcripts: [TranscriptRecord] = []
    var recoveryText = ""
    private(set) var lastInsertionReceipt: InsertionReceipt?
    var historyRetentionLimit: Int {
        didSet {
            historyRetentionLimit = max(0, historyRetentionLimit)
            UserDefaults.standard.set(historyRetentionLimit, forKey: "historyRetentionLimit")
            reloadTranscriptStore()
        }
    }
    private(set) var isReading = false
    private(set) var readingProfileID: String?
    private var readingOperationID: UUID?
    private var performanceSnapshot: PerformanceSnapshot?

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
        voiceIdentifier = savedVoice.isEmpty ? MacTextService.defaultVoice : savedVoice
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
        historyRetentionLimit = UserDefaults.standard.object(forKey: "historyRetentionLimit") == nil
            ? TranscriptStore.defaultRetentionLimit
            : max(0, UserDefaults.standard.integer(forKey: "historyRetentionLimit"))

        assert(Set(HotKeyOption.dictationChoices).isDisjoint(with: HotKeyOption.readingChoices))

        do {
            transcriptStore = try TranscriptStore.applicationSupport(
                retentionLimit: historyRetentionLimit
            )
            transcripts = try transcriptStore?.recent(limit: historyRetentionLimit) ?? []
        } catch {
            transcriptStoreError = error.localizedDescription
        }

        dictation.onCommitCandidate = { [weak self] operationID, text in
            Task { @MainActor in
                await self?.saveAndInsert(text, operationID: operationID)
            }
        }
        dictation.resolveArtifact = { [weak self] profileID in
            guard let self else { throw CancellationError() }
            return try self.profiles.artifact(forID: profileID)
        }
        hotKeys.onDictation = { [weak self] in self?.toggleDictation() }
        hotKeys.onReadSelection = { [weak self] in self?.readSelection() }
        hotKeys.start()
        configureHotKeys()
        refreshPermissions()
        if let transcriptStoreError {
            statusMessage = "History unavailable: \(transcriptStoreError)"
        } else if let pendingStoreError = dictation.pendingStoreError {
            statusMessage = pendingStoreError.localizedDescription
        } else if dictation.pendingResult != nil {
            statusMessage = "A pending transcription was recovered"
        }
        recoveryText = dictation.pendingResult?.text ?? ""
        performanceSnapshot = .capture(launchStartedAt: launchStartedAt)
    }

    func toggleDictation() {
        if dictation.isRecording || dictation.isTranscribing {
            dictation.toggle(language: transcriptionLanguageCode)
            return
        }

        guard ensureAccessibilityPermission() else { return }

        do {
            let artifact = try profiles.artifact(for: .dictation)
            macText.rememberInsertionTarget()
            dictation.toggle(language: transcriptionLanguageCode, artifact: artifact)
        } catch {
            dictation.showUnavailable(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func cancelDictation() {
        dictation.cancel()
    }

    var hasPendingRecovery: Bool { dictation.pendingResult != nil }
    var canUndoInsertion: Bool { lastInsertionReceipt?.verifiedInsertion != nil }

    func copyRecoveryText() {
        macText.copy(recoveryText)
        statusMessage = "Copied pending transcription"
    }

    func retryInsertion() {
        Task {
            do {
                try dictation.updatePendingText(recoveryText)
                let receipt = try await dictation.retryPendingResult { [weak self] text, operationID in
                    guard let self else { return .failedRecoverable(.noFocusedControl) }
                    return await macText.insert(text, operationID: operationID)
                }
                applyInsertionReceipt(receipt)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func discardRecovery() {
        do {
            try dictation.discardPendingResult()
            recoveryText = ""
            statusMessage = "Discarded pending transcription"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func retainRecoveryToHistory() {
        do {
            guard !recoveryText.isEmpty, let transcriptStore else {
                throw TranscriptStoreError.sqlite(transcriptStoreError ?? "The database is unavailable.")
            }
            if transcripts.first?.text != recoveryText {
                try transcriptStore.insert(recoveryText)
            }
            transcripts = try transcriptStore.recent(limit: historyRetentionLimit)
            try dictation.discardPendingResult()
            recoveryText = ""
            statusMessage = "Retained transcription in history"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func undoLastInsertion() {
        guard let insertion = lastInsertionReceipt?.verifiedInsertion else {
            statusMessage = "Undo is unavailable because the prior insertion was not verified."
            return
        }
        if let refusal = macText.undo(insertion) {
            statusMessage = refusal
        } else {
            lastInsertionReceipt = nil
            statusMessage = "Undid verified insertion"
        }
    }

    func readSelection() {
        guard ensureAccessibilityPermission() else { return }

        Task {
            do {
                let artifact = try profiles.artifact(for: .reading)
                try validateVoice(voiceIdentifier)
                let operationID = UUID()
                isReading = true
                readingProfileID = artifact.profileID
                readingOperationID = operationID
                defer {
                    if readingOperationID == operationID {
                        isReading = false
                        readingProfileID = nil
                        readingOperationID = nil
                    }
                }
                let text = try await macText.selectedText()
                statusMessage = "Generating speech"
                try await macText.speak(
                    text,
                    voiceIdentifier: voiceIdentifier,
                    rate: Float(speechRate),
                    volume: Float(speechVolume),
                    artifact: artifact
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
                let artifact = try profiles.artifact(for: .reading)
                try validateVoice(identifier)
                statusMessage = "Generating voice preview"
                let operationID = UUID()
                isReading = true
                readingProfileID = artifact.profileID
                readingOperationID = operationID
                defer {
                    if readingOperationID == operationID {
                        isReading = false
                        readingProfileID = nil
                        readingOperationID = nil
                    }
                }
                try await macText.speak(
                    Self.previewText(for: identifier),
                    voiceIdentifier: identifier,
                    rate: Float(speechRate),
                    volume: Float(speechVolume),
                    artifact: artifact
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

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
            statusMessage = "Microphone access is enabled"
        case .notDetermined:
            Task {
                microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                statusMessage = microphoneGranted
                    ? "Microphone access is enabled"
                    : "Microphone access is required for dictation"
            }
        default:
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ) else { return }
            NSWorkspace.shared.open(url)
            statusMessage = "Enable tk under Privacy & Security → Microphone"
        }
    }

    func refreshPermissions() {
        accessibilityGranted = macText.hasAccessibilityPermission
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func profileInUse(_ profile: SpeechProfile) -> Bool {
        return profile.kind == .dictation
            ? dictation.activeProfileID == profile.id
            : readingProfileID == profile.id
    }

    func retryHotKeys() {
        configureHotKeys()
    }

    func deleteTranscript(_ transcript: TranscriptRecord) throws {
        guard let transcriptStore else {
            throw TranscriptStoreError.sqlite(transcriptStoreError ?? "The database is unavailable.")
        }
        try transcriptStore.delete(id: transcript.id)
        transcripts.removeAll { $0.id == transcript.id }
    }

    func clearTranscriptHistory() throws {
        guard let transcriptStore else {
            throw TranscriptStoreError.sqlite(transcriptStoreError ?? "The database is unavailable.")
        }
        try transcriptStore.clear()
        transcripts.removeAll()
    }

    func transcriptExportData() throws -> Data {
        guard let transcriptStore else {
            throw TranscriptStoreError.sqlite(transcriptStoreError ?? "The database is unavailable.")
        }
        return try transcriptStore.exportData()
    }

    func diagnosticsData() throws -> Data {
        let availability = Dictionary(uniqueKeysWithValues: profiles.availability.map {
            ($0.key, DiagnosticsProfileAvailability($0.value))
        })
        let performance = performanceSnapshot ?? .capture(launchStartedAt: launchStartedAt)
        var measurements = [
            "appLaunchMilliseconds": performance.appLaunchMilliseconds,
            "residentMemoryMegabytes": performance.residentMemoryMegabytes,
        ]
        var budgetResults = performance.budgetResults
        if let dictationStart = dictation.lastStartMilliseconds {
            measurements["dictationStartMilliseconds"] = dictationStart
            budgetResults[PerformanceBudget.dictationStart.name] = PerformanceBudget.dictationStart.contains(dictationStart)
        }
        return try DiagnosticsReport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            profileAvailability: availability,
            accessibilityPermissionGranted: accessibilityGranted,
            microphonePermissionGranted: microphoneGranted,
            status: DiagnosticsStatus(sanitizing: statusMessage),
            performanceMeasurements: measurements,
            performanceBudgetsPassed: budgetResults
        ).exportedData()
    }

    private func configureHotKeys() {
        statusMessage = hotKeys.configure(
            dictation: dictationShortcut,
            reading: readShortcut
        ) ? "Shortcuts ready" : "A shortcut is already used by another app"
    }

    private func reloadTranscriptStore() {
        do {
            transcriptStore = try TranscriptStore.applicationSupport(
                retentionLimit: historyRetentionLimit
            )
            transcripts = try transcriptStore?.recent(limit: historyRetentionLimit) ?? []
            transcriptStoreError = nil
            statusMessage = "History retention updated"
        } catch {
            transcriptStoreError = error.localizedDescription
            statusMessage = "History unavailable: \(error.localizedDescription)"
        }
    }

    private func validateVoice(_ identifier: String) throws {
        guard availableVoices.contains(identifier) else {
            throw MacTextError.speechFailed(
                "The saved voice is unavailable. Choose another voice in Read Aloud."
            )
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        refreshPermissions()
        guard accessibilityGranted else {
            requestAccessibility()
            return false
        }
        return true
    }

    private func saveAndInsert(_ text: String, operationID: UUID) async {
        do {
            let receipt = try await dictation.commitCandidate(operationID: operationID) { [weak self] text in
                guard let self else { return .failedRecoverable(.noFocusedControl) }
                do {
                    guard let transcriptStore else {
                        throw TranscriptStoreError.sqlite(
                            transcriptStoreError ?? "The database is unavailable."
                        )
                    }
                    try transcriptStore.insert(text)
                    transcripts = try transcriptStore.recent(limit: historyRetentionLimit)
                    transcriptStoreError = nil
                } catch {
                    transcriptStoreError = error.localizedDescription
                }
                return await macText.insert(text, operationID: operationID)
            }
            applyInsertionReceipt(receipt)
        } catch {
            statusMessage = transcriptStoreError.map {
                "History could not be saved: \($0). Insertion also failed: \(error.localizedDescription)"
            } ?? error.localizedDescription
        }
    }

    private func applyInsertionReceipt(_ receipt: InsertionReceipt) {
        lastInsertionReceipt = receipt
        switch receipt {
        case .verified:
            recoveryText = ""
            statusMessage = transcriptStoreError.map {
                "Inserted, but history could not be saved: \($0)"
            } ?? "Inserted transcription"
        case .attempted:
            recoveryText = dictation.pendingResult?.text ?? recoveryText
            statusMessage = "Insertion was attempted but could not be verified; text remains pending"
        case .copyOnly:
            recoveryText = dictation.pendingResult?.text ?? recoveryText
            statusMessage = "Text was copied but could not be pasted; text remains pending"
        case .failedRecoverable:
            recoveryText = dictation.pendingResult?.text ?? recoveryText
            statusMessage = "Insertion target changed or is unsupported; text remains pending"
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

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
