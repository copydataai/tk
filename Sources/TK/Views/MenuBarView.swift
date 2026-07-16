import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some View {
        Button(model.dictation.isRecording ? "Stop & Insert" : "Start Dictation") {
            model.toggleDictation()
        }
        Button("Read Selection") {
            model.readSelection()
        }
        Button("Stop Reading") {
            model.stopSpeaking()
        }

        Divider()

        Button("Open tk") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
