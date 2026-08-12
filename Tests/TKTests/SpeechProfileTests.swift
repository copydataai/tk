import Foundation
import XCTest
@testable import TK

final class SpeechProfileTests: XCTestCase {
    @MainActor
    func testDownloadsAndVerifiesOptionalProfiles() async throws {
        guard ProcessInfo.processInfo.environment["TK_RUN_PROFILE_DOWNLOAD_TESTS"] == "1" else {
            throw XCTSkip("Set TK_RUN_PROFILE_DOWNLOAD_TESTS=1 to download the pinned profile artifacts.")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "SpeechProfileDownloadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SpeechProfileStore(
            defaults: defaults,
            modelDirectory: directory.appendingPathComponent("models"),
            resourceDirectory: directory.appendingPathComponent("resources")
        )

        for profile in SpeechProfile.all where !profile.isBundled {
            store.download(profile)
            let deadline = Date().addingTimeInterval(30 * 60)
            while store.downloadingProfileID != nil, Date() < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }

            XCTAssertNil(store.downloadingProfileID, "Timed out downloading \(profile.id)")
            XCTAssertEqual(store.availability[profile.id], .available)
            let artifact = try store.artifact(forID: profile.id)
            XCTAssertEqual(
                try artifact.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                Int(profile.byteCount)
            )
        }
    }

    @MainActor
    func testManifestAndSavedSelectionContract() throws {
        XCTAssertEqual(
            SpeechProfile.all.map(\.id),
            [
                "dictation.fast",
                "dictation.balanced",
                "dictation.best-quality",
                "reading.lower-memory",
                "reading.best-quality",
            ]
        )
        XCTAssertEqual(Set(SpeechProfile.all.map(\.id)).count, SpeechProfile.all.count)
        XCTAssertEqual(Set(SpeechProfile.all.map(\.filename)).count, SpeechProfile.all.count)
        XCTAssertTrue(SpeechProfile.all.allSatisfy { $0.downloadURL.scheme == "https" })
        XCTAssertEqual(
            SpeechProfile.all.map {
                "\($0.id)|\($0.filename)|\($0.byteCount)|\($0.sha256)|\($0.downloadURL.absoluteString)|\($0.isBundled)"
            },
            [
                "dictation.fast|ggml-small-q5_1.bin|190085487|ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb|https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin|false",
                "dictation.balanced|ggml-large-v3-turbo-q5_0.bin|574041195|394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2|https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin|true",
                "dictation.best-quality|ggml-large-v3-q5_0.bin|1081140203|d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1|https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin|false",
                "reading.lower-memory|kokoro-v1.0-quantized.onnx|92361116|fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478|https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model_quantized.onnx|false",
                "reading.best-quality|kokoro-v1.0-fp32.onnx|325532232|8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb|https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model.onnx|true",
            ]
        )

        let suite = "SpeechProfileTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dictation.future", forKey: SpeechProfileStore.dictationKey)
        defaults.set("INVALID VALUE", forKey: SpeechProfileStore.readingKey)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpeechProfileStore(
            defaults: defaults,
            modelDirectory: directory.appendingPathComponent("models"),
            resourceDirectory: directory.appendingPathComponent("resources")
        )

        XCTAssertEqual(store.selectedDictationID, "dictation.future")
        XCTAssertEqual(store.selectedReadingID, "reading.best-quality")
        XCTAssertThrowsError(try store.artifact(for: .dictation)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The saved profile is not available in this version of tk. Choose another profile in Settings."
            )
        }
    }

    @MainActor
    func testBundledArtifactsNeverFallBackToDownloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let models = directory.appendingPathComponent("models")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        let bundled = try XCTUnwrap(SpeechProfile.all.first { $0.id == "dictation.balanced" })
        FileManager.default.createFile(
            atPath: models.appendingPathComponent(bundled.filename).path,
            contents: Data()
        )
        let suite = "SpeechProfileFallbackTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dictation.fast", forKey: SpeechProfileStore.dictationKey)
        let store = SpeechProfileStore(
            defaults: defaults,
            modelDirectory: models,
            resourceDirectory: directory.appendingPathComponent("resources")
        )

        XCTAssertEqual(
            store.availability[bundled.id],
            .failed("The bundled profile is missing. Reinstall tk.")
        )
        let selected = try XCTUnwrap(SpeechProfile.all.first { $0.id == "dictation.fast" })
        XCTAssertThrowsError(try store.remove(selected))
        XCTAssertEqual(store.selectedDictationID, selected.id)
    }
}
