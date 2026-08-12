@preconcurrency import AVFoundation
import AppKit
import Foundation

enum SystemContinuityEvent: Equatable, Sendable {
    enum ResourcePressure: Equatable, Sendable {
        case degraded
        case blocked
        case normal
    }

    case willSleep
    case didWake
    case audioDeviceConnected(id: String)
    case audioDeviceDisconnected(id: String)
    case resourcePressure(ResourcePressure)
}

enum ContinuityDecision: Equatable, Sendable {
    case continueCurrentOperation
    case continueDegraded(message: String)
    case interruptRecoverably(message: String, preserveAudio: Bool)
    case resourceBlocked(message: String, preserveAudio: Bool)
}

enum ContinuityNotification: Equatable, Sendable {
    case interruptedRecoverable
    case degraded
    case resourceBlocked

    var title: String {
        switch self {
        case .interruptedRecoverable: "Dictation interrupted"
        case .degraded: "Dictation degraded"
        case .resourceBlocked: "Dictation blocked"
        }
    }
}

enum ContinuityPolicy {
    static func decision(
        for event: SystemContinuityEvent,
        transactionState: DictationTransaction.State?,
        capturedDeviceID: String?
    ) -> ContinuityDecision {
        guard let transactionState,
              [.preparing, .recording, .finalizing, .recognizing].contains(transactionState) else {
            return .continueCurrentOperation
        }

        switch event {
        case .willSleep:
            if transactionState == .recognizing {
                return .interruptRecoverably(
                    message: "Dictation was interrupted while this Mac slept. Audio was preserved for recovery.",
                    preserveAudio: true
                )
            }
            return .interruptRecoverably(
                message: "Dictation stopped because this Mac went to sleep. No transcription was completed.",
                preserveAudio: false
            )
        case .didWake:
            if transactionState == .recognizing {
                return .interruptRecoverably(
                    message: "Dictation was interrupted while this Mac slept. Audio was preserved for recovery.",
                    preserveAudio: true
                )
            }
            return .interruptRecoverably(
                message: "Dictation was interrupted by system wake. Start a new dictation after devices are checked.",
                preserveAudio: false
            )
        case .audioDeviceDisconnected(let id):
            guard transactionState == .recording,
                  MicrophoneCapture.isCapturedDeviceDisconnect(
                    disconnectedDeviceID: id,
                    capturedDeviceID: capturedDeviceID
                  ) else {
                return .continueCurrentOperation
            }
            return .interruptRecoverably(
                message: "The recording microphone disconnected. Dictation stopped without switching microphones.",
                preserveAudio: false
            )
        case .audioDeviceConnected:
            return .continueCurrentOperation
        case .resourcePressure(.normal):
            return .continueCurrentOperation
        case .resourcePressure(.degraded):
            return .continueDegraded(
                message: "System resources are constrained. Current recognition will continue without changing profiles."
            )
        case .resourcePressure(.blocked):
            guard transactionState == .recognizing else {
                return .resourceBlocked(
                    message: "Dictation stopped because system resources are critically constrained. No transcription was completed.",
                    preserveAudio: false
                )
            }
            return .resourceBlocked(
                message: "Recognition stopped because system resources are critically constrained. Audio was preserved for recovery.",
                preserveAudio: true
            )
        }
    }

    static func requiresDeviceReprobe(after event: SystemContinuityEvent) -> Bool {
        if case .didWake = event { return true }
        return false
    }
}

@MainActor
final class SystemContinuityMonitor {
    var onEvent: ((SystemContinuityEvent) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.deliver(.willSleep) })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.deliver(.didWake) })

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            self?.deliver(.audioDeviceConnected(id: device.uniqueID))
        })
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            self?.deliver(.audioDeviceDisconnected(id: device.uniqueID))
        })
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.deliver(Self.currentThermalPressure) })

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            if event.contains(.critical) {
                self?.onEvent?(.resourcePressure(.blocked))
            } else if event.contains(.warning) {
                self?.onEvent?(.resourcePressure(.degraded))
            } else {
                self?.onEvent?(.resourcePressure(.normal))
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            center.removeObserver(observer)
        }
        observers.removeAll()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private nonisolated func deliver(_ event: SystemContinuityEvent) {
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }

    private nonisolated static var currentThermalPressure: SystemContinuityEvent {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .resourcePressure(.normal)
        case .fair, .serious: .resourcePressure(.degraded)
        case .critical: .resourcePressure(.blocked)
        @unknown default: .resourcePressure(.degraded)
        }
    }

    deinit {
        memoryPressureSource?.cancel()
    }
}
