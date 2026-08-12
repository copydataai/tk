import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some View {
        Button(
            model.dictation.isTranscribing
                ? "Transcribing…"
                : model.dictation.isRecording ? "Stop & Insert" : "Start Dictation"
        ) {
            model.toggleDictation()
        }
        .disabled(model.dictation.isTranscribing)
        Button("Read Selection") {
            model.readSelection()
        }
        Button("Stop Reading") {
            model.stopSpeaking()
        }

        if model.hasPendingRecovery {
            Divider()
            Text(model.recoveryText)
            Button("Copy Pending Transcription") { model.copyRecoveryText() }
            Button("Retry Insertion") { model.retryInsertion() }
            Button("Retain to History") { model.retainRecoveryToHistory() }
            Button("Discard Pending Transcription", role: .destructive) {
                model.discardRecovery()
            }
        }
        if model.canUndoInsertion {
            Button("Undo Verified Insertion") { model.undoLastInsertion() }
        }

        Divider()

        Button("Show Flow Bar") {
            openWindow(id: "flow-bar")
        }
        Button("Open tk") {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                openWindow(id: "main")
                revealMainWindow()
            }
        }
        SettingsLink()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
