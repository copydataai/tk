import XCTest
@testable import TK

final class InferenceAdmissionTests: XCTestCase {
    func testSelectedProfileNeverSilentlyFallsBackWhenMemoryIsInsufficient() {
        let outcome = policy.evaluate(preflight(availableMemory: 99, requiredMemory: 100))
        XCTAssertEqual(outcome, .selectedProfileUnavailable("large-v3"))
    }

    func testAllPreflightBoundariesRejectBeforeAdmission() {
        XCTAssertEqual(policy.evaluate(preflight(format: "mp3")), .unsupportedAudioFormat)
        XCTAssertEqual(policy.evaluate(preflight(pressure: .critical)), .memoryPressure)
        XCTAssertEqual(policy.evaluate(preflight(helper: false)), .helperUnavailable)
        XCTAssertEqual(policy.evaluate(preflight(active: 1)), .busy)
    }

    func testReceiptIsContentFreeAndHardwareThresholdIsExplicit() throws {
        let receipt = InferencePerformanceReceipt(
            operationID: UUID(), profileID: "large-v3", coldStart: true,
            startupMilliseconds: 20, inferenceMilliseconds: 400,
            peakMemoryBytes: 1_000, termination: .exited,
            cleanupSucceeded: true, responseBytes: 42
        )
        let data = try JSONEncoder().encode(receipt)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("transcript"))
        XCTAssertEqual(HardwarePerformanceThreshold(
            hardwareIdentifier: "Mac15,6", profileID: "large-v3",
            maximumInferenceMilliseconds: 2_000, maximumPeakMemoryBytes: 8_000
        ).hardwareIdentifier, "Mac15,6")
    }

    private var policy: InferenceAdmissionPolicy {
        .init(maxDuration: 10, maxAudioBytes: 100, allowedFormats: ["wav"], maxConcurrency: 1)
    }

    private func preflight(
        format: String = "wav", availableMemory: UInt64 = 100,
        requiredMemory: UInt64 = 100, pressure: MemoryPressureLevel = .normal,
        helper: Bool = true, active: Int = 0
    ) -> InferencePreflight {
        .init(duration: 1, audioBytes: 10, audioFormat: format,
              availableMemoryBytes: availableMemory, memoryPressure: pressure,
              helperAvailable: helper,
              profile: .init(profileID: "large-v3", requiredMemoryBytes: requiredMemory, device: "cpu"),
              activeOperations: active)
    }
}
