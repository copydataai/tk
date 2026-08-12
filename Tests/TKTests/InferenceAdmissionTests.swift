import XCTest
@testable import TK

final class InferenceAdmissionTests: XCTestCase {
    func testRuntimeWiringRejectsLowLiveAvailableMemory() async throws {
        let runtime = WhisperRuntime(probes: .test(availableMemoryBytes: 99))

        let outcome = try await runtime.admissionOutcomeForTesting(requiredMemoryBytes: 100)

        XCTAssertEqual(outcome, .selectedProfileUnavailable("large-v3"))
    }

    func testRuntimeWiringRejectsCriticalLivePressure() async throws {
        let runtime = WhisperRuntime(probes: .test(memoryPressure: .critical))

        let outcome = try await runtime.admissionOutcomeForTesting(requiredMemoryBytes: 100)

        XCTAssertEqual(outcome, .memoryPressure)
    }

    func testRuntimeWiringRejectsMissingLiveHelper() async throws {
        let runtime = WhisperRuntime(probes: .test(helperAvailable: false))

        let outcome = try await runtime.admissionOutcomeForTesting(requiredMemoryBytes: 100)

        XCTAssertEqual(outcome, .helperUnavailable)
    }

    func testRuntimeWiringRejectsProcessWideConcurrentOperation() async throws {
        let runtime = WhisperRuntime(probes: .test(activeOperations: 1))

        let outcome = try await runtime.admissionOutcomeForTesting(requiredMemoryBytes: 100)

        XCTAssertEqual(outcome, .busy)
    }

    func testRuntimeWiringFailsRecoverablyWhenLiveProbeIsIndeterminate() async {
        let runtime = WhisperRuntime(probes: .test(failure: ProbeFailure.indeterminate))

        do {
            _ = try await runtime.admissionOutcomeForTesting(requiredMemoryBytes: 100)
            XCTFail("Expected an unavailable admission state")
        } catch {
            XCTAssertEqual(error as? WhisperRuntimeError, .admissionStateUnavailable)
        }
    }

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

private extension InferenceLiveProbes {
    static func test(
        availableMemoryBytes: UInt64 = 100,
        memoryPressure: MemoryPressureLevel = .normal,
        helperAvailable: Bool = true,
        activeOperations: Int = 0,
        failure: Error? = nil
    ) -> Self {
        .init(
            availableMemoryBytes: { if let failure { throw failure }; return availableMemoryBytes },
            memoryPressure: { if let failure { throw failure }; return memoryPressure },
            helperAvailable: { _ in if let failure { throw failure }; return helperAvailable },
            activeOperations: { if let failure { throw failure }; return activeOperations }
        )
    }
}

private enum ProbeFailure: Error { case indeterminate }
