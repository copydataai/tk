import AppKit
import SwiftUI

let flowAccent = Color(red: 1, green: 0.38, blue: 0.27)

private enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case readAloud = "Read aloud"
    case settings = "Settings"

    var id: Self { self }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .readAloud: "speaker.wave.2"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppModel
    @State private var selection: HubSection? = .home
    @State private var didOpenFlowBar = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(flowAccent, in: RoundedRectangle(cornerRadius: 9))
                    Text("tk")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                List(HubSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Label(
                    model.accessibilityGranted ? "Ready everywhere" : "Permission needed",
                    systemImage: model.accessibilityGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            switch selection ?? .home {
            case .home:
                HomeView(model: model)
            case .history:
                HistoryView(model: model)
            case .readAloud:
                ReadAloudView(model: model)
            case .settings:
                SettingsView(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(flowAccent)
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            guard !didOpenFlowBar else { return }
            didOpenFlowBar = true
            openWindow(id: "flow-bar")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshPermissions()
        }
    }
}

private struct HomeView: View {
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
                                    : "mic.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .disabled(model.dictation.isTranscribing)
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
                            model.transcripts.isEmpty
                                ? "Your latest transcription will appear here."
                                : model.transcripts[0].text
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

private struct HistoryView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.transcripts.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "text.quote",
                    description: Text("Completed dictations will appear here.")
                )
            } else {
                List(model.transcripts) { transcript in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transcript.text)
                            .textSelection(.enabled)
                        Text(
                            transcript.createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("History")
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

private struct ReadAloudView: View {
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
            ForEach(localeIdentifiers, id: \.self) { identifier in
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

    private var localeIdentifiers: [String] {
        Array(Set(model.availableVoices.map(Self.localeIdentifier(for:)))).sorted {
            Self.localeName(for: $0) < Self.localeName(for: $1)
        }
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

private struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
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
            }

            Section("Status") {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
