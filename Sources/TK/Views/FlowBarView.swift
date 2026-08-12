import AppKit
import SwiftUI

struct FlowBarView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 8) {
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
                    isActive: model.dictation.isRecording
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
                .help(model.canRetryInsertion ? "Stop and insert" : "Stop and prepare transcription to copy")
                .accessibilityLabel(model.canRetryInsertion
                    ? "Stop recording and insert transcription"
                    : "Stop recording and prepare transcription to copy")
            } else if model.dictation.isPreparing {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
                    .font(.callout.weight(.medium))
                    .padding(.trailing, 4)
            } else if model.dictation.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing locally…")
                    .font(.callout.weight(.medium))
                    .padding(.trailing, 4)
            } else {
                Button {
                    model.toggleDictation()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(flowAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Start dictation — \(model.dictationShortcut.label)")
                .accessibilityLabel("Start dictation")
            }
            }
            if model.hasPendingRecovery {
                RecoveryActionsView(model: model, compact: true)
                    .frame(width: 520)
            }
            if model.canUndoInsertion {
                Button("Undo verified insertion") { model.undoLastInsertion() }
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
        .accessibilityValue(accessibilityValue)
    }

    @MainActor
    private var accessibilityValue: String {
        if model.dictation.isRecording { return "Listening" }
        if model.dictation.isPreparing { return "Starting" }
        if model.dictation.isTranscribing { return "Transcribing" }
        return "Ready"
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
