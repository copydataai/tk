import Foundation

struct DictationActivity {
    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var isFinalizing = false
    private(set) var isTranscribing = false
    private var shouldTranscribe = false

    mutating func beginPreparing() {
        isPreparing = true
    }

    mutating func cancelPreparation() {
        isPreparing = false
    }

    mutating func beginRecording() {
        isPreparing = false
        isRecording = true
        shouldTranscribe = false
    }

    mutating func finishRecording(shouldTranscribe: Bool) {
        isRecording = false
        isFinalizing = true
        isTranscribing = shouldTranscribe
        self.shouldTranscribe = shouldTranscribe
    }

    mutating func completeRecording() -> Bool {
        isFinalizing = false
        let result = shouldTranscribe
        shouldTranscribe = false
        return result
    }

    mutating func completeTranscription() {
        isTranscribing = false
    }
}
