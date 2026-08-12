import Darwin
import Foundation

struct PerformanceSnapshot: Equatable, Sendable {
    let appLaunchMilliseconds: Double
    let residentMemoryMegabytes: Double

    var budgetResults: [String: Bool] {
        [
            PerformanceBudget.appLaunch.name: PerformanceBudget.appLaunch.contains(appLaunchMilliseconds),
            PerformanceBudget.idleMemory.name: PerformanceBudget.idleMemory.contains(residentMemoryMegabytes),
        ]
    }

    static func capture(launchStartedAt: ContinuousClock.Instant) -> PerformanceSnapshot {
        let elapsed = launchStartedAt.duration(to: .now)
        return PerformanceSnapshot(
            appLaunchMilliseconds: elapsed.milliseconds,
            residentMemoryMegabytes: residentMemoryMegabytes()
        )
    }

    private static func residentMemoryMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
