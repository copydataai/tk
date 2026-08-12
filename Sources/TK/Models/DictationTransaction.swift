import Foundation

struct PendingDictation: Codable, Equatable, Sendable {
    enum Trust: String, Codable, Sendable {
        case locallyRecognized
    }

    enum CommitState: String, Codable, Sendable {
        case ready
        case inserting
        case insertionFailed
    }

    let operationID: UUID
    var text: String
    let createdAt: Date
    let profileID: String
    let trust: Trust
    var commitState: CommitState
}

struct DictationTransaction: Equatable, Sendable {
    enum State: String, CaseIterable, Sendable {
        case preparing
        case recording
        case finalizing
        case recognizing
        case resultReady
        case committing
        case retained
        case discarded
        case cancelled
        case interruptedRecoverable
        case failedRecoverable
        case failedTerminal
    }

    enum AudioState: Equatable, Sendable {
        case pending
        case capturing
        case available(URL)
        case discarded
    }

    struct Failure: Error, Equatable, Sendable {
        enum Kind: String, Sendable {
            case permission
            case capture
            case recognition
            case insertion
            case history
            case unavailableProfile
            case interruption
            case resourceBlocked
        }

        let kind: Kind
        let message: String
    }

    struct InvalidTransition: Error, Equatable {
        let from: State
        let to: State
    }

    let operationID: UUID
    let startedAt: Date
    let profileID: String
    private(set) var updatedAt: Date
    private(set) var state: State
    private(set) var audioState: AudioState
    private(set) var candidateText: String?
    private(set) var failure: Failure?

    init(
        operationID: UUID = UUID(),
        profileID: String,
        startedAt: Date = Date()
    ) {
        self.operationID = operationID
        self.startedAt = startedAt
        self.profileID = profileID
        updatedAt = startedAt
        state = .preparing
        audioState = .pending
    }

    mutating func transition(to nextState: State, at date: Date = Date()) throws {
        guard Self.allowedTransitions[state, default: []].contains(nextState) else {
            throw InvalidTransition(from: state, to: nextState)
        }
        state = nextState
        updatedAt = date
    }

    mutating func setCandidateText(_ text: String, at date: Date = Date()) throws {
        guard state == .recognizing else {
            throw InvalidTransition(from: state, to: .resultReady)
        }
        candidateText = text
        try transition(to: .resultReady, at: date)
    }

    mutating func setAudioState(_ audioState: AudioState, at date: Date = Date()) {
        self.audioState = audioState
        updatedAt = date
    }

    mutating func fail(
        _ failure: Failure,
        recoverable: Bool,
        at date: Date = Date()
    ) throws {
        let failureState: State = recoverable ? .failedRecoverable : .failedTerminal
        try transition(to: failureState, at: date)
        self.failure = failure
    }

    mutating func interruptRecoverably(message: String, at date: Date = Date()) throws {
        try transition(to: .interruptedRecoverable, at: date)
        failure = .init(kind: .interruption, message: message)
    }

    private static let allowedTransitions: [State: Set<State>] = [
        .preparing: [.recording, .cancelled, .interruptedRecoverable, .failedRecoverable, .failedTerminal],
        .recording: [.finalizing, .cancelled, .interruptedRecoverable, .failedRecoverable, .failedTerminal],
        .finalizing: [.recognizing, .discarded, .cancelled, .interruptedRecoverable, .failedRecoverable, .failedTerminal],
        .recognizing: [.resultReady, .discarded, .cancelled, .interruptedRecoverable, .failedRecoverable, .failedTerminal],
        .resultReady: [.committing, .discarded, .cancelled],
        .committing: [.retained, .failedRecoverable, .failedTerminal],
        .failedRecoverable: [.committing, .discarded, .cancelled],
        .interruptedRecoverable: [.discarded, .cancelled]
    ]
}
