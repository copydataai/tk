import Foundation

struct PerformanceBudget: Equatable, Sendable {
    enum Unit: String, Equatable, Sendable {
        case milliseconds
        case megabytes
    }

    let name: String
    let maximum: Double
    let unit: Unit

    func contains(_ measurement: Double) -> Bool {
        measurement.isFinite && measurement >= 0 && measurement <= maximum
    }
}

extension PerformanceBudget {
    static let appLaunch = PerformanceBudget(
        name: "App launch",
        maximum: 1_000,
        unit: .milliseconds
    )
    static let dictationStart = PerformanceBudget(
        name: "Dictation start",
        maximum: 250,
        unit: .milliseconds
    )
    static let idleMemory = PerformanceBudget(
        name: "Idle memory",
        maximum: 250,
        unit: .megabytes
    )

    static let declared: [PerformanceBudget] = [appLaunch, dictationStart, idleMemory]
}
