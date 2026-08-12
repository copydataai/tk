struct OnboardingReadiness {
    let accessibilityGranted: Bool
    let microphoneGranted: Bool

    var canGetStarted: Bool {
        accessibilityGranted && microphoneGranted
    }
}
