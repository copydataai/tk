import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tk")
                        .font(.largeTitle.bold())
                    Text("Private voice tools for your Mac")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Voice to text") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Press once to listen, then press again to insert the transcription at the cursor.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Picker("Shortcut", selection: $model.dictationShortcut) {
                            ForEach(HotKeyOption.dictationChoices) { shortcut in
                                Text(shortcut.label).tag(shortcut)
                            }
                        }
                        .frame(width: 190)
                        Spacer()
                        Button(
                            model.dictation.isTranscribing
                                ? "Transcribing…"
                                : model.dictation.isRecording ? "Stop & Insert" : "Start Dictation"
                        ) {
                            model.toggleDictation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.dictation.isTranscribing)
                    }
                    if !model.dictation.transcript.isEmpty {
                        Text(model.dictation.transcript)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text(model.dictation.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Read selected text") {
                VStack(spacing: 12) {
                    HStack {
                        Picker("Shortcut", selection: $model.readShortcut) {
                            ForEach(HotKeyOption.readingChoices) { shortcut in
                                Text(shortcut.label).tag(shortcut)
                            }
                        }
                        .frame(width: 190)
                        Spacer()
                        Button("Stop") { model.stopSpeaking() }
                        Button("Read Selection") { model.readSelection() }
                    }

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Voice")
                            Picker("Voice", selection: $model.voiceIdentifier) {
                                ForEach(model.availableVoices, id: \.self) { voice in
                                    Text(voice).tag(voice)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Speed")
                            HStack {
                                Slider(
                                    value: $model.speechRate,
                                    in: 0.5...2
                                )
                                Text(model.speechRate, format: .number.precision(.fractionLength(2)))
                                    .monospacedDigit()
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                        GridRow {
                            Text("Volume")
                            HStack {
                                Slider(value: $model.speechVolume, in: 0...1)
                                Text(model.speechVolume, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(6)
            }

            HStack {
                Label(
                    model.accessibilityGranted ? "Accessibility enabled" : "Accessibility required",
                    systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                Spacer()
                if !model.accessibilityGranted {
                    Button("Enable…") { model.requestAccessibility() }
                }
            }

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }
}
