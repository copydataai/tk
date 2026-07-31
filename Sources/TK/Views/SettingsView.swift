import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Transcription language", selection: $model.transcriptionLanguageCode) {
                    Text("Auto").tag(String?.none)
                    Text("English").tag(String?.some("en"))
                    Text("Spanish").tag(String?.some("es"))
                    Text("French").tag(String?.some("fr"))
                    Text("German").tag(String?.some("de"))
                    Text("Italian").tag(String?.some("it"))
                    Text("Portuguese").tag(String?.some("pt"))
                    Text("Japanese").tag(String?.some("ja"))
                    Text("Chinese").tag(String?.some("zh"))
                }
                Text("Auto detects the spoken language. Choose one to improve recognition when you know it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                Picker("Dictation", selection: $model.dictationShortcut) {
                    ForEach(HotKeyOption.dictationChoices) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                Picker("Read selected text", selection: $model.readShortcut) {
                    ForEach(HotKeyOption.readingChoices) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
            }

            Section("System access") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(model.accessibilityGranted ? "Enabled" : "Required")
                            .foregroundStyle(.secondary)
                        if !model.accessibilityGranted {
                            Button("Enable…") { model.requestAccessibility() }
                        }
                    }
                }
                Text("Accessibility lets tk insert text into the focused app and read your selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Microphone") {
                    HStack {
                        Text(model.microphoneGranted ? "Enabled" : "Required")
                            .foregroundStyle(.secondary)
                        if !model.microphoneGranted {
                            Button("Enable…") { model.requestMicrophone() }
                        }
                    }
                }
            }

            Section("Status") {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 440)
    }
}
