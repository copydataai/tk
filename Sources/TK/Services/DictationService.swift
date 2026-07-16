@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class DictationService {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var status = "Press the shortcut to dictate"

    var onTranscriptReady: ((String) -> Void)?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?

    func toggle() {
        if isRecording {
            finish(insertTranscript: true)
        } else {
            requestPermissionsAndStart()
        }
    }

    private func requestPermissionsAndStart() {
        status = "Requesting speech permission…"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            Task { @MainActor in
                guard let self else { return }
                guard authorization == .authorized else {
                    self.status = "Speech recognition permission is required"
                    return
                }
                self.requestMicrophonePermission()
            }
        }
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startRecording()
                    } else {
                        self.status = "Microphone permission is required"
                    }
                }
            }
        default:
            status = "Microphone permission is required"
        }
    }

    private func startRecording() {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            status = "Speech recognition is unavailable for this language"
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "On-device recognition is unavailable for this language"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = "No microphone input is available"
            return
        }

        transcript = ""
        self.recognizer = recognizer
        recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            status = "Listening — press the shortcut again to insert"
        } catch {
            inputNode.removeTap(onBus: 0)
            status = "Could not start the microphone: \(error.localizedDescription)"
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal, self.isRecording {
                        self.finish(insertTranscript: true)
                    }
                } else if let error, self.isRecording {
                    self.finish(insertTranscript: false)
                    self.status = "Dictation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finish(insertTranscript: Bool) {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        isRecording = false

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if insertTranscript, !text.isEmpty {
            onTranscriptReady?(text)
            status = "Transcription ready"
        } else {
            status = text.isEmpty ? "Nothing heard" : "Dictation stopped"
        }
    }
}
