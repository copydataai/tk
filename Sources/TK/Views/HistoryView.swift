import SwiftUI

struct HistoryView: View {
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
