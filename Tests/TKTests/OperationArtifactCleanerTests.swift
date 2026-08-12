import Foundation
import XCTest
@testable import TK

final class OperationArtifactCleanerTests: XCTestCase {
    func testCreatesPrivateOwnedOperationDirectoryWithContentFreeMarker() throws {
        let fixture = try ArtifactCleanerFixture()
        defer { fixture.remove() }
        let operationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let artifacts = try fixture.cleaner().createOperation(operationID: operationID)

        XCTAssertEqual(artifacts.recordingURL.lastPathComponent, "recording.caf")
        XCTAssertEqual(artifacts.wavURL.lastPathComponent, "speech.wav")
        let attributes = try FileManager.default.attributesOfItem(atPath: artifacts.directoryURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        let marker = try String(
            contentsOf: artifacts.directoryURL.appendingPathComponent("owner.json"),
            encoding: .utf8
        )
        XCTAssertTrue(marker.contains(operationID.uuidString))
        XCTAssertFalse(marker.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(marker.localizedCaseInsensitiveContains("text"))
    }

    func testCleanupRemovesOnlyStaleOwnedDirectoriesInDeterministicOrder() throws {
        let fixture = try ArtifactCleanerFixture()
        defer { fixture.remove() }
        let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let fresh = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let now = Date(timeIntervalSince1970: 10_000)
        try fixture.makeOwnedOperation(first, modifiedAt: now.addingTimeInterval(-101))
        try fixture.makeOwnedOperation(second, modifiedAt: now.addingTimeInterval(-200))
        try fixture.makeOwnedOperation(fresh, modifiedAt: now.addingTimeInterval(-99))
        let unrelated = fixture.rootURL.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let report = fixture.cleaner(now: now).cleanupStale()

        XCTAssertEqual(report.removedOperationIDs, [first, second])
        XCTAssertEqual(report.retainedFreshCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDirectory(fixture, fresh).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testCleanupRetainsStaleDirectoryOwnedByVerifiedLiveProcess() throws {
        let fixture = try ArtifactCleanerFixture()
        defer { fixture.remove() }
        let operationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let now = Date(timeIntervalSince1970: 10_000)
        try fixture.makeOwnedOperation(operationID, modifiedAt: now.addingTimeInterval(-200))

        let report = fixture.cleaner(now: now, processIsLive: { _ in true }).cleanupStale()

        XCTAssertEqual(report.retainedLiveCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDirectory(fixture, operationID).path))
    }

    func testCleanupNeverTraversesOutsideOwnedRoot() throws {
        let fixture = try ArtifactCleanerFixture()
        defer { fixture.remove() }
        let outside = fixture.parentURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: sentinel)
        let link = fixture.rootURL.appendingPathComponent("linked-operation")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        _ = fixture.cleaner(now: Date(timeIntervalSince1970: 10_000)).cleanupStale()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    private func freshDirectory(_ fixture: ArtifactCleanerFixture, _ id: UUID) -> URL {
        fixture.rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }
}

private struct ArtifactCleanerFixture {
    let parentURL: URL
    let rootURL: URL

    init() throws {
        parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        rootURL = parentURL.appendingPathComponent("tk-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleaner(
        now: Date = Date(timeIntervalSince1970: 10_000),
        processIsLive: @escaping @Sendable (ResidentProcessRecord) -> Bool = { _ in false }
    ) -> OperationArtifactCleaner {
        OperationArtifactCleaner(
            rootURL: rootURL,
            staleAge: 100,
            now: { now },
            processIsLive: processIsLive
        )
    }

    func makeOwnedOperation(_ id: UUID, modifiedAt: Date) throws {
        let artifacts = try cleaner().createOperation(operationID: id)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: artifacts.directoryURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: parentURL)
    }
}
