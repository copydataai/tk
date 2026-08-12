import SwiftUI

struct RecoveryActionsView: View {
    let model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insertion needs attention")
                .font(.headline)
            TextEditor(text: Binding(
                get: { model.recoveryText },
                set: { model.recoveryText = $0 }
            ))
            .font(.body)
            .frame(minHeight: compact ? 52 : 82)
            .border(.separator)
            HStack {
                Button("Copy") { model.copyRecoveryText() }
                Button("Retry insertion") { model.retryInsertion() }
                    .disabled(!model.canRetryInsertion)
                    .help("Requires Accessibility permission")
                Button("Retain to history") { model.retainRecoveryToHistory() }
                Button("Discard", role: .destructive) { model.discardRecovery() }
            }
            .controlSize(compact ? .small : .regular)
        }
        .padding(compact ? 10 : 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending transcription recovery")
    }
}
