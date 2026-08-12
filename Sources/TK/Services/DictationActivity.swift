import Foundation

struct DictationActivity {
    let transaction: DictationTransaction?

    var isPreparing: Bool { transaction?.state == .preparing }
    var isRecording: Bool { transaction?.state == .recording }
    var isFinalizing: Bool { transaction?.state == .finalizing }
    var isTranscribing: Bool { transaction?.state == .recognizing }
}
