import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        revealMainWindow()
    }
}

@MainActor
func revealMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: \.canBecomeMain) else { return }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct TKApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("tk", id: "main") {
            ContentView(model: model)
                .onAppear {
                    revealMainWindow()
                }
        }
        .defaultSize(width: 920, height: 680)

        Window("tk Flow Bar", id: "flow-bar") {
            FlowBarView(model: model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model)
        }

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
