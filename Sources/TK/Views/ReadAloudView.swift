import SwiftUI

struct ReadAloudView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("Hear selected text with a high-quality local Kokoro voice.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Read selection") { model.readSelection() }
                        .buttonStyle(.borderedProminent)
                        .tint(flowAccent)
                    Button("Stop") { model.stopSpeaking() }
                }
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Voice") {
                VoicePicker(model: model)
                SliderRow(
                    title: "Speed",
                    value: $model.speechRate,
                    range: 0.5...2,
                    valueLabel: model.speechRate.formatted(
                        .number.precision(.fractionLength(2))
                    )
                )
                SliderRow(
                    title: "Volume",
                    value: $model.speechVolume,
                    range: 0...1,
                    valueLabel: model.speechVolume.formatted(
                        .percent.precision(.fractionLength(0))
                    )
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Read aloud")
    }
}

private struct VoicePicker: View {
    @Bindable var model: AppModel
    @State private var localeIdentifier: String

    init(model: AppModel) {
        self.model = model
        localeIdentifier = Self.localeIdentifier(for: model.voiceIdentifier)
        assert(
            Self.localeIdentifier(for: "en-US-heart") == "en_US"
                && Self.voiceName(for: "en-US-heart") == "Heart"
        )
    }

    var body: some View {
        Picker("Language", selection: $localeIdentifier) {
            ForEach(Self.localeIdentifiers, id: \.self) { identifier in
                Text(Self.localeName(for: identifier)).tag(identifier)
            }
        }

        Picker("Voice", selection: $model.voiceIdentifier) {
            ForEach(voices, id: \.self) { voice in
                Text(Self.voiceName(for: voice)).tag(voice)
            }
        }

        Button {
            model.previewVoice(model.voiceIdentifier)
        } label: {
            Label("Preview voice", systemImage: "play.fill")
        }
        .onChange(of: localeIdentifier) {
            guard !voices.contains(model.voiceIdentifier),
                  let first = voices.first else { return }
            model.voiceIdentifier = first
        }
    }

    private static let localeIdentifiers = Array(
        Set(MacTextService.availableVoices.map(localeIdentifier(for:)))
    ).sorted {
        localeName(for: $0) < localeName(for: $1)
    }

    private var voices: [String] {
        model.availableVoices
            .filter { Self.localeIdentifier(for: $0) == localeIdentifier }
    }

    private static func localeIdentifier(for voice: String) -> String {
        voice.split(separator: "-").prefix(2).joined(separator: "_")
    }

    private static func localeName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private static func voiceName(for identifier: String) -> String {
        identifier.split(separator: "-").dropFirst(2)
            .joined(separator: " ")
            .capitalized
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueLabel: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(valueLabel)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            .frame(maxWidth: 340)
        }
    }
}
