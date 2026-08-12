import Foundation
import XCTest
@testable import TK

final class LocalInferenceSessionTests: XCTestCase {
    func testRejectsOversizeAudioBeforeLaunchingHelper() async throws {
        let fixture = try Fixture(script: "touch \"$TK_MARKER\"\n")
        defer { fixture.remove() }
        try Data(repeating: 0, count: 9).write(to: fixture.audioURL)
        let session = fixture.session(maxAudioBytes: 8)

        await XCTAssertThrowsErrorAsync {
            try await session.transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .audioTooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.markerURL.path))
    }

    func testRunsOneOperationWithoutOpeningReusableListener() async throws {
        let fixture = try Fixture(script: """
        printf '%s\n' "$@" >"$TK_ARGUMENTS"
        output=""
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--output-file" ]]; then output="$2"; shift 2; else shift; fi
        done
        printf ' boundary result \n' >"$output.txt"
        """)
        defer { fixture.remove() }

        let result = try await fixture.session().transcribe(
            audioURL: fixture.audioURL,
            declaredDuration: 1,
            language: "en"
        )

        XCTAssertEqual(result, "boundary result")
        let arguments = try String(contentsOf: fixture.argumentsURL, encoding: .utf8)
        XCTAssertFalse(arguments.contains("--host"))
        XCTAssertFalse(arguments.contains("--port"))
        XCTAssertFalse(arguments.localizedCaseInsensitiveContains("token"))
    }

    func testRejectsInvalidDeclaredDurationBeforeLaunchingHelper() async throws {
        let fixture = try Fixture(script: "touch \"$TK_MARKER\"\n")
        defer { fixture.remove() }

        await XCTAssertThrowsErrorAsync {
            try await fixture.session().transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 11,
                language: "en"
            )
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .invalidDuration)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.markerURL.path))
    }

    func testRejectsConcurrentInferenceAtTheProcessBoundary() async throws {
        let fixture = try Fixture(script: """
        output=""
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--output-file" ]]; then output="$2"; shift 2; else shift; fi
        done
        touch "$TK_MARKER"
        sleep 2
        printf 'done\n' >"$output.txt"
        """)
        defer { fixture.remove() }
        let session = fixture.session(timeout: 5)
        let first = Task {
            try await session.transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        }
        try await waitForFile(fixture.markerURL)

        await XCTAssertThrowsErrorAsync {
            try await session.transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .busy)
        }
        first.cancel()
        _ = try? await first.value
    }

    func testCancellationTerminatesHelperAndRemovesOperationDirectory() async throws {
        let fixture = try Fixture(script: "touch \"$TK_MARKER\"\nsleep 30\n")
        defer { fixture.remove() }
        let session = fixture.session(timeout: 60)
        let task = Task {
            try await session.transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        }
        try await waitForFile(fixture.markerURL)

        task.cancel()
        await XCTAssertThrowsErrorAsync { try await task.value } verify: { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.workURL.path), [])
    }

    func testTimeoutKillsForkedDescendantInDedicatedProcessGroup() async throws {
        let fixture = try Fixture(script: """
        sleep 30 &
        echo $! >"$TK_MARKER"
        wait
        """)
        defer { fixture.remove() }
        let session = fixture.session(timeout: 0.5)

        await XCTAssertThrowsErrorAsync {
            try await session.transcribe(audioURL: fixture.audioURL, declaredDuration: 1, language: "en")
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .timedOut)
        }

        let pid = Int32((try String(contentsOf: fixture.markerURL, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertEqual(kill(pid, 0), -1)
    }

    func testRejectsOversizeHelperResponse() async throws {
        let fixture = try Fixture(script: """
        output=""
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--output-file" ]]; then output="$2"; shift 2; else shift; fi
        done
        printf '123456789' >"$output.txt"
        """)
        defer { fixture.remove() }

        await XCTAssertThrowsErrorAsync {
            try await fixture.session(maxResponseBytes: 8).transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .responseTooLarge)
        }
    }

    func testTimeoutTerminatesHelperAndCleansState() async throws {
        let fixture = try Fixture(script: "touch \"$TK_MARKER\"\nsleep 30\n")
        defer { fixture.remove() }

        await XCTAssertThrowsErrorAsync {
            try await fixture.session(timeout: 0.05).transcribe(
                audioURL: fixture.audioURL,
                declaredDuration: 1,
                language: "en"
            )
        } verify: { error in
            XCTAssertEqual(error as? LocalInferenceSession.Error, .timedOut)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.workURL.path), [])
    }
}

private struct Fixture {
    let rootURL: URL
    let executableURL: URL
    let modelURL: URL
    let vadModelURL: URL
    let audioURL: URL
    let markerURL: URL
    let argumentsURL: URL
    let workURL: URL

    init(script: String) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        executableURL = rootURL.appendingPathComponent("fake-whisper")
        modelURL = rootURL.appendingPathComponent("model.bin")
        vadModelURL = rootURL.appendingPathComponent("vad.bin")
        audioURL = rootURL.appendingPathComponent("audio.wav")
        markerURL = rootURL.appendingPathComponent("started")
        argumentsURL = rootURL.appendingPathComponent("arguments")
        workURL = rootURL.appendingPathComponent("operations", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "#!/bin/bash\nset -euo pipefail\n\(script)".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        try Data("model".utf8).write(to: modelURL)
        try Data("vad".utf8).write(to: vadModelURL)
        try Data("audio".utf8).write(to: audioURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
    }

    func session(
        maxAudioBytes: Int = 1024,
        maxResponseBytes: Int = 1024,
        timeout: TimeInterval = 5
    ) -> LocalInferenceSession {
        LocalInferenceSession(
            executableURL: executableURL,
            modelURL: modelURL,
            vadModelURL: vadModelURL,
            operationRootURL: workURL,
            environment: [
                "TK_ARGUMENTS": argumentsURL.path,
                "TK_MARKER": markerURL.path,
            ],
            limits: .init(
                maxAudioBytes: maxAudioBytes,
                maxDuration: 10,
                maxResponseBytes: maxResponseBytes,
                timeout: timeout
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func waitForFile(_ url: URL) async throws {
    for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    XCTFail("Timed out waiting for helper boundary")
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    verify: (Swift.Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        verify(error)
    }
}
