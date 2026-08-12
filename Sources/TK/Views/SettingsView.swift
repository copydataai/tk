import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var destination = SettingsDestination.speechProfiles

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: $destination) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch destination {
            case .general: GeneralSettings(model: model)
            case .speechProfiles: SpeechProfilesSettings(model: model)
            case .shortcuts: ShortcutSettings(model: model)
            case .systemAccess: SystemAccessSettings(model: model)
            }
        }
        .frame(minWidth: 760, idealWidth: 760, minHeight: 480, idealHeight: 600)
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case speechProfiles
    case shortcuts
    case systemAccess

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .speechProfiles: "Speech profiles"
        case .shortcuts: "Shortcuts"
        case .systemAccess: "System access"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .speechProfiles: "waveform"
        case .shortcuts: "command"
        case .systemAccess: "hand.raised"
        }
    }
}

@MainActor
private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Transcription language", selection: $model.transcriptionLanguageCode) {
                    Text("Auto").tag(String?.none)
                    ForEach([
                        ("English", "en"), ("Spanish", "es"), ("French", "fr"),
                        ("German", "de"), ("Italian", "it"), ("Portuguese", "pt"),
                        ("Japanese", "ja"), ("Chinese", "zh"),
                    ], id: \.1) { name, code in
                        Text(name).tag(String?.some(code))
                    }
                }
                Text("Auto detects the spoken language. Choose one to improve recognition when you know it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.dictationModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                Picker("Keep transcripts", selection: $model.historyRetentionLimit) {
                    Text("Do not keep history").tag(0)
                    Text("Last 25").tag(25)
                    Text("Last 50").tag(50)
                    Text("Last 100").tag(100)
                    Text("Last 500").tag(500)
                }
                Text("Microphone audio is never retained. Stored transcripts are marked as untrusted speech recognition and ineligible for agent use. Retention changes apply immediately and do not remove a separately pending recovery result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Clear All uses SQLite secure_delete, checkpoints and truncates the WAL, and reports selected application-controlled files. It does not claim SSD secure erasure or deletion from snapshots or backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Button("Export Diagnostics…") {
                    exportDiagnostics()
                }
                Text("The report contains app and system status only. It excludes transcript text and audio paths.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Recovery") {
                Button("Refresh Permissions") { model.refreshPermissions() }
                Button("Retry Shortcuts") { model.retryHotKeys() }
                if !model.accessibilityGranted {
                    Button("Open Accessibility Settings") { model.requestAccessibility() }
                }
                if !model.microphoneGranted {
                    Button("Open Microphone Settings") { model.requestMicrophone() }
                }
            }
            Section("Status") {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .alert("Diagnostics Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "An unknown error occurred.")
        }
    }

    private func exportDiagnostics() {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "tk-diagnostics.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try model.diagnosticsData().write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

@MainActor
private struct ShortcutSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker("Dictation", selection: $model.dictationShortcut) {
                ForEach(HotKeyOption.dictationChoices) { Text($0.label).tag($0) }
            }
            Picker("Read selected text", selection: $model.readShortcut) {
                ForEach(HotKeyOption.readingChoices) { Text($0.label).tag($0) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}

@MainActor
private struct SystemAccessSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Accessibility") {
                HStack {
                    Text(model.accessibilityGranted ? "Enabled" : "Required")
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
                    if !model.microphoneGranted {
                        Button("Enable…") { model.requestMicrophone() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System access")
    }
}

@MainActor
private struct SpeechProfilesSettings: View {
    @Bindable var model: AppModel
    @State private var profileToRemove: SpeechProfile?
    @State private var removalError: String?

    var body: some View {
        Form {
            Section {
                Label("Everything runs privately on this Mac.", systemImage: "lock.shield")
                    .font(.headline)
                Text("Optional profile downloads use the internet only when you request them. Dictation and reading remain offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            profileSection(
                title: "Dictation quality",
                kind: .dictation,
                limits: "Dictation may miss, repeat, or invent words. Results vary with language, accent, background noise, and microphone quality."
            )
            profileSection(
                title: "Reading quality",
                kind: .reading,
                limits: "Voices support German, Greek, English (UK and US), French, Italian, Japanese, Brazilian Portuguese, and Chinese. Pronunciation can vary."
            )
            Section("Technical details") {
                DisclosureGroup("Models, runtimes, and notices") {
                    ForEach(SpeechProfile.all) { profile in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name).font(.headline)
                            Text(profile.filename).textSelection(.enabled)
                            Text("\(profile.byteCount.formatted()) bytes · \(profile.sourceRevision)")
                            Text("\(profile.runtimeIdentity) · \(profile.supportedTarget)")
                            Text(profile.licenseSummary)
                            Text("SHA-256 \(profile.sha256)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speech profiles")
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { profileToRemove != nil },
                set: { if !$0 { profileToRemove = nil } }
            )
        ) {
            if let profileToRemove {
                Button(removalButtonTitle(for: profileToRemove), role: .destructive) {
                    do {
                        try model.profiles.remove(profileToRemove)
                        self.profileToRemove = nil
                    } catch {
                        removalError = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) { self.profileToRemove = nil }
            }
        }
        .alert("Couldn’t remove profile", isPresented: Binding(
            get: { removalError != nil },
            set: { if !$0 { removalError = nil } }
        )) {
            Button("OK") { removalError = nil }
        } message: {
            Text(removalError ?? "The profile could not be removed.")
        }
    }

    @ViewBuilder
    private func profileSection(
        title: String,
        kind: SpeechProfileKind,
        limits: String
    ) -> some View {
        Section(title) {
            if model.profiles.selectedProfile(for: kind) == nil {
                Label(
                    "Saved choice \(model.profiles.selectedID(for: kind)) is unavailable in this version. Choose an available profile.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
            }
            if model.profiles.downloadingProfileID != nil {
                Text("Another download is in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.profiles.profiles(for: kind)) { profile in
                profileRow(profile)
            }
            DisclosureGroup(kind == .dictation ? "Dictation limits" : "Reading limits") {
                Text(limits).foregroundStyle(.secondary)
            }
        }
    }

    private func profileRow(_ profile: SpeechProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.profiles.select(profile) } label: {
                Image(systemName: model.profiles.isSelected(profile) ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(model.profiles.availability[profile.id]?.canSelect != true)
            .accessibilityLabel("Select \(profile.name)")
            .accessibilityAddTraits(model.profiles.isSelected(profile) ? .isSelected : [])
            .accessibilityHint(
                model.profiles.availability[profile.id]?.canSelect == true
                    ? ""
                    : model.profiles.unavailableMessage(for: profile)
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(profile.name).font(.headline)
                    if profile.id == SpeechProfile.defaultIDs[profile.kind] {
                        Text("Recommended").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(profile.downloadSize) · \(profile.memory)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Best for: \(profile.bestFor)")
                    .font(.caption)
                if let notice = profile.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                profileState(profile)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func profileState(_ profile: SpeechProfile) -> some View {
        let state = model.profiles.availability[profile.id] ?? .missing
        switch state {
        case .available:
            HStack {
                Text(availableLabel(for: profile))
                if profile.isBundled {
                    Text("Included")
                } else {
                    Button("Remove…") { profileToRemove = profile }
                        .disabled(model.profileInUse(profile))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Verifying…") }
                .font(.caption)
        case .missing:
            HStack {
                Text(model.profiles.isSelected(profile) ? "Selected · Unavailable" : "Not downloaded")
                Button("Download") { model.profiles.download(profile) }
                    .disabled(model.profiles.downloadingProfileID != nil)
            }
            .font(.caption)
        case .downloading:
            VStack(alignment: .leading) {
                Text("Downloading \(profile.name)…")
                ProgressView(
                    value: Double(model.profiles.downloadedBytes),
                    total: Double(profile.byteCount)
                )
                .accessibilityLabel("Downloading \(profile.name)")
                .accessibilityValue("\(model.profiles.downloadedBytes.formatted(.byteCount(style: .file))) of \(profile.byteCount.formatted(.byteCount(style: .file)))")
                Text("\(model.profiles.downloadedBytes.formatted(.byteCount(style: .file))) of \(profile.byteCount.formatted(.byteCount(style: .file)))")
                    .monospacedDigit()
                Button("Cancel") { model.profiles.cancelDownload() }
            }
            .font(.caption)
        case .interrupted(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(model.profiles.isSelected(profile) ? "Selected · Unavailable" : "Interrupted")
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { model.profiles.download(profile) }
                    .disabled(model.profiles.downloadingProfileID != nil)
            }
            .font(.caption)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(model.profiles.isSelected(profile) ? "Selected · Unavailable" : "Unavailable")
                Text(message).foregroundStyle(.secondary)
                HStack {
                    Button(
                        model.profiles.hasInstalledArtifact(profile) ? "Repair download" : "Try again"
                    ) { model.profiles.download(profile) }
                        .disabled(model.profiles.downloadingProfileID != nil)
                    if model.profiles.hasInstalledArtifact(profile) {
                        Button("Remove…") { profileToRemove = profile }
                            .disabled(model.profileInUse(profile))
                    }
                }
            }
            .font(.caption)
        }
    }

    private var removalTitle: String {
        guard let profileToRemove else { return "Remove profile?" }
        return "Remove \(profileToRemove.name)?"
    }

    private func availableLabel(for profile: SpeechProfile) -> String {
        guard model.profiles.isSelected(profile) else {
            return profile.isBundled ? "Available" : "Downloaded"
        }
        if !profile.isBundled { return "Selected · Downloaded" }
        return profile.id == SpeechProfile.defaultIDs[profile.kind]
            ? "Selected · Recommended"
            : "Selected"
    }

    private func removalButtonTitle(for profile: SpeechProfile) -> String {
        guard model.profiles.isSelected(profile),
              let defaultID = SpeechProfile.defaultIDs[profile.kind],
              let defaultProfile = SpeechProfile.all.first(where: { $0.id == defaultID }) else {
            return "Remove"
        }
        return "Switch to \(defaultProfile.name) and remove"
    }
}
