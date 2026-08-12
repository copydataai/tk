import AppKit
import SwiftUI

@MainActor
struct HistoryView: View {
    let model: AppModel
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?
    @State private var deletionReceiptMessage: String?

    var body: some View {
        Group {
            if model.transcripts.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "text.quote",
                    description: Text("Completed dictations will appear here.")
                )
            } else {
                List {
                    ForEach(model.transcripts) { transcript in
                        HStack(alignment: .top, spacing: 12) {
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
                                Text("Untrusted speech recognition, agent ineligible")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(transcript)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Delete transcript")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup {
                Button("Export", systemImage: "square.and.arrow.up") {
                    exportHistory()
                }
                .disabled(model.transcripts.isEmpty && !model.hasPendingRecovery)

                Button("Clear All", systemImage: "trash", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled(model.transcripts.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all transcript history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("Clears transcript rows, checkpoints and truncates SQLite WAL data, and removes selected corrupt archives and the pending dictation artifact. SSD secure erasure, snapshots, and backups are excluded.")
        }
        .alert("History Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Deletion Receipt", isPresented: Binding(
            get: { deletionReceiptMessage != nil },
            set: { if !$0 { deletionReceiptMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionReceiptMessage ?? "")
        }
    }

    private func delete(_ transcript: TranscriptRecord) {
        do {
            try model.deleteTranscript(transcript)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        do {
            let receipt = try model.clearTranscriptHistory()
            let stores = receipt.successes.map { $0.store.rawValue }.joined(separator: ", ")
            let exclusions = receipt.exclusions.joined(separator: " ")
            deletionReceiptMessage = "\(receipt.summary) Stores: \(stores). Exclusions: \(exclusions)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportHistory() {
        do {
            let data = try model.transcriptExportData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "tk-transcript-history.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
