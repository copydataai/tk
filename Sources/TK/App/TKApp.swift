import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct TKApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("tk", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 920, height: 680)

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(
                "tk",
                systemImage: model.dictation.isRecording ? "waveform.circle.fill" : "waveform.circle"
            )
        }
    }
}
