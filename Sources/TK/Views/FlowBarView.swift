import AppKit
import SwiftUI

struct FlowBarView: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.dictation.isRecording {
                Button {
                    model.cancelDictation()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel dictation")

                Divider()
                    .frame(height: 22)

                Image(systemName: "waveform")
                    .font(.title3.bold())
                    .foregroundStyle(flowAccent)
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: true
                    )
                Text("Listening")
                    .font(.callout.weight(.medium))

                Button {
                    model.toggleDictation()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(flowAccent)
                .help("Stop and insert")
            } else if model.dictation.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing locally…")
                    .font(.callout.weight(.medium))
                    .padding(.trailing, 4)
            } else {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("EN")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .help("Open tk")

                Divider()
                    .frame(height: 20)

                Button {
                    model.toggleDictation()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(flowAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Start dictation — \(model.dictationShortcut.label)")

                Divider()
                    .frame(height: 20)

                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Open settings")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.24))
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(16)
        .background(FloatingWindowConfigurator())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tk dictation bar")
    }
}

private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view, coordinator: context.coordinator)
    }

    private func configure(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask = [.borderless]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.titleVisibility = .hidden

            guard !coordinator.didPosition,
                  let screen = window.screen ?? NSScreen.main else { return }
            let frame = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: frame.midX - window.frame.width / 2,
                    y: frame.minY + 36
                )
            )
            coordinator.didPosition = true
        }
    }

    final class Coordinator {
        var didPosition = false
    }
}
