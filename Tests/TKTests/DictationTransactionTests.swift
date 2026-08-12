import Foundation
import XCTest
@testable import TK

final class DictationTransactionTests: XCTestCase {
    func testHappyPathRequiresResultReadyBeforeCommitting() throws {
        let operationID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var transaction = DictationTransaction(
            operationID: operationID,
            profileID: "dictation-profile",
            startedAt: startedAt
        )

        try transaction.transition(to: .recording, at: startedAt.addingTimeInterval(1))
        try transaction.transition(to: .finalizing, at: startedAt.addingTimeInterval(2))
        try transaction.transition(to: .recognizing, at: startedAt.addingTimeInterval(3))
        try transaction.setCandidateText("hello", at: startedAt.addingTimeInterval(4))

        XCTAssertEqual(transaction.state, .resultReady)
        XCTAssertEqual(transaction.candidateText, "hello")
        var prematureCommit = DictationTransaction(profileID: "other")
        XCTAssertThrowsError(try prematureCommit.transition(to: .committing))

        try transaction.transition(to: .committing, at: startedAt.addingTimeInterval(5))
        try transaction.transition(to: .retained, at: startedAt.addingTimeInterval(6))

        XCTAssertEqual(transaction.operationID, operationID)
        XCTAssertEqual(transaction.profileID, "dictation-profile")
        XCTAssertEqual(transaction.startedAt, startedAt)
        XCTAssertEqual(transaction.updatedAt, startedAt.addingTimeInterval(6))
    }

    func testIllegalTransitionsAreRejectedWithoutChangingState() {
        var transaction = DictationTransaction(profileID: "profile")

        XCTAssertThrowsError(try transaction.transition(to: .recognizing))
        XCTAssertEqual(transaction.state, .preparing)
    }

    func testInsertionFailureRetainsCandidateTextForRecovery() throws {
        var transaction = try resultReadyTransaction(candidateText: "keep me")
        try transaction.transition(to: .committing)

        try transaction.fail(
            .init(kind: .insertion, message: "No insertion target"),
            recoverable: true
        )

        XCTAssertEqual(transaction.state, .failedRecoverable)
        XCTAssertEqual(transaction.candidateText, "keep me")
        XCTAssertEqual(transaction.failure?.kind, .insertion)
    }

    func testCancellationIsTerminalDuringEveryPreResultPhase() throws {
        for phase in [
            DictationTransaction.State.preparing,
            .recording,
            .finalizing,
            .recognizing
        ] {
            var transaction = DictationTransaction(profileID: "profile")
            for nextState in path(after: .preparing, through: phase) {
                try transaction.transition(to: nextState)
            }

            try transaction.transition(to: .cancelled)

            XCTAssertEqual(transaction.state, .cancelled)
            XCTAssertThrowsError(try transaction.transition(to: .recording))
        }
    }

    func testAudioStateRecordsObservedCaptureAndArtifactAvailability() throws {
        let audioURL = URL(fileURLWithPath: "/tmp/dictation.caf")
        var transaction = DictationTransaction(profileID: "profile")

        transaction.setAudioState(.capturing)
        try transaction.transition(to: .recording)
        transaction.setAudioState(.available(audioURL))

        XCTAssertEqual(transaction.audioState, .available(audioURL))
    }

    func testContinuityInterruptionIsRecoverableFromEveryPreResultPhase() throws {
        for phase in [
            DictationTransaction.State.preparing,
            .recording,
            .finalizing,
            .recognizing
        ] {
            var transaction = DictationTransaction(profileID: "profile")
            for nextState in path(after: .preparing, through: phase) {
                try transaction.transition(to: nextState)
            }

            try transaction.interruptRecoverably(message: "System interruption")

            XCTAssertEqual(transaction.state, .interruptedRecoverable)
            XCTAssertEqual(transaction.failure?.kind, .interruption)
        }
    }

    private func resultReadyTransaction(candidateText: String) throws -> DictationTransaction {
        var transaction = DictationTransaction(profileID: "profile")
        try transaction.transition(to: .recording)
        try transaction.transition(to: .finalizing)
        try transaction.transition(to: .recognizing)
        try transaction.setCandidateText(candidateText)
        return transaction
    }

    private func path(
        after initialState: DictationTransaction.State,
        through finalState: DictationTransaction.State
    ) -> [DictationTransaction.State] {
        let phases: [DictationTransaction.State] = [.preparing, .recording, .finalizing, .recognizing]
        let initialIndex = phases.firstIndex(of: initialState)!
        let finalIndex = phases.firstIndex(of: finalState)!
        guard initialIndex < finalIndex else { return [] }
        return Array(phases[(initialIndex + 1)...finalIndex])
    }
}
