import XCTest
@testable import TK

final class PerformanceBudgetTests: XCTestCase {
    func testDeclaredBudgetsAreStable() {
        XCTAssertEqual(
            PerformanceBudget.declared,
            [
                PerformanceBudget(name: "App launch", maximum: 1_000, unit: .milliseconds),
                PerformanceBudget(name: "Dictation start", maximum: 250, unit: .milliseconds),
                PerformanceBudget(name: "Idle memory", maximum: 250, unit: .megabytes),
            ]
        )
    }

    func testBudgetAcceptsOnlyFiniteNonnegativeMeasurementsAtOrBelowMaximum() {
        let budget = PerformanceBudget(name: "Operation", maximum: 250, unit: .milliseconds)

        XCTAssertTrue(budget.contains(0))
        XCTAssertTrue(budget.contains(250))
        XCTAssertFalse(budget.contains(250.01))
        XCTAssertFalse(budget.contains(-1))
        XCTAssertFalse(budget.contains(.infinity))
        XCTAssertFalse(budget.contains(.nan))
    }

    func testSnapshotReportsEachMeasuredBudget() {
        let snapshot = PerformanceSnapshot(
            appLaunchMilliseconds: 500,
            residentMemoryMegabytes: 300
        )

        XCTAssertEqual(snapshot.budgetResults[PerformanceBudget.appLaunch.name], true)
        XCTAssertEqual(snapshot.budgetResults[PerformanceBudget.idleMemory.name], false)
    }
}
