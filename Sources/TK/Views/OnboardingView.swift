import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 58, height: 58)
                    .background(flowAccent, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to tk")
                        .font(.title.bold())
                    Text("Private dictation and reading, processed on your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                SetupRow(
                    title: "Accessibility",
                    detail: "Insert dictated text and read your selection.",
                    isReady: model.accessibilityGranted,
                    action: model.requestAccessibility
                )
                Divider()
                SetupRow(
                    title: "Microphone",
                    detail: "Record your voice for local transcription.",
                    isReady: model.microphoneGranted,
                    action: model.requestMicrophone
                )
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator)
            }

            Label("Speech models are included and work offline.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Set Up Later", action: finish)
                Spacer()
                Button("Get Started", action: finish)
                    .buttonStyle(.borderedProminent)
                    .tint(flowAccent)
                    .disabled(!OnboardingReadiness(
                        accessibilityGranted: model.accessibilityGranted,
                        microphoneGranted: model.microphoneGranted
                    ).canGetStarted)
            }
        }
        .padding(32)
        .frame(width: 560)
        .onAppear(perform: model.refreshPermissions)
    }
}

private struct SetupRow: View {
    let title: String
    let detail: String
    let isReady: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isReady ? .green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isReady ? "Enabled" : "Enable…", action: action)
                .disabled(isReady)
        }
        .padding(16)
    }
}
