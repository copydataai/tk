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
