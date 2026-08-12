import AppKit
import SwiftUI

@MainActor
struct HomeView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to tk")
                        .font(.system(size: 30, weight: .bold))
                    Text("Private voice tools, right where you type.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("DICTATE ANYWHERE", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(.black.opacity(0.65))
                        Text("Press \(model.dictationShortcut.label) and speak")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.black)
                        Text("Press it again to transcribe locally and insert at your cursor.")
                            .foregroundStyle(.black.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            model.toggleDictation()
                        } label: {
                            Label(
                                dictationButtonTitle,
                                systemImage: model.dictation.isRecording
                                    ? "stop.fill"
                                    : "waveform"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .disabled(model.dictation.isTranscribing)
                        Text(model.dictation.status)
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.65))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 20)
                    Image(systemName: "waveform")
                        .font(.system(size: 70, weight: .light))
                        .foregroundStyle(.black.opacity(0.75))
                        .symbolEffect(
                            .variableColor.iterative,
                            options: .repeating,
                            isActive: model.dictation.isRecording
                        )
                }
                .padding(26)
                .background(
                    LinearGradient(
                        colors: [flowAccent, flowAccent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20)
                )

                if model.hasPendingRecovery {
                    RecoveryActionsView(model: model)
                }

                if model.canUndoInsertion {
                    Button("Undo verified insertion") {
                        model.undoLastInsertion()
                    }
                    Text("Undo is available only while the verified target and inserted content are unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    StatusTile(value: "100%", label: "Local processing")
                    StatusTile(value: "24 kHz", label: "Voice output")
                    StatusTile(value: "Offline", label: "After setup")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent activity")
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "text.quote")
                                .foregroundStyle(flowAccent)
                            Text(model.transcripts.isEmpty ? "No dictations yet" : "Latest dictation")
                                .font(.headline)
                            Spacer()
                            Text(
                                model.transcripts.first?.createdAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ) ?? model.dictation.status
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            model.transcripts.first?.text
                                ?? "Your latest transcription will appear here."
                        )
                        .foregroundStyle(
                            model.transcripts.isEmpty ? .secondary : .primary
                        )
                        .textSelection(.enabled)
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.separator.opacity(0.6))
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var dictationButtonTitle: String {
        if model.dictation.isTranscribing { return "Transcribing…" }
        return model.dictation.isRecording ? "Stop & insert" : "Start dictation"
    }
}

private struct StatusTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.5))
        }
    }
}
