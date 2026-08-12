struct OnboardingReadiness {
    let accessibilityGranted: Bool
    let microphoneGranted: Bool

    var canGetStarted: Bool {
        microphoneGranted
    }
}

struct DictationAuthority {
    enum Mode: Equatable {
        case automaticInsertion
        case copy
    }

    let accessibilityGranted: Bool

    var mode: Mode { accessibilityGranted ? .automaticInsertion : .copy }
    var mayCaptureInsertionTarget: Bool { accessibilityGranted }
    var mayInsertAutomatically: Bool { accessibilityGranted }
    var mayCopyToClipboard: Bool { true }
}
