import XCTest
@testable import TK

final class UpdateControllerTests: XCTestCase {
    @MainActor
    func testDevelopmentBundleLeavesUpdatesDisabledWithoutSignedConfiguration() {
        let controller = UpdateController(bundle: Bundle(for: Self.self))

        XCTAssertFalse(controller.isEnabled)
    }

    @MainActor
    func testOnlyHTTPSFeedAndNonemptyPublicKeyEnableUpdateConfiguration() {
        XCTAssertTrue(UpdateController.hasValidConfiguration(
            feedURL: "https://updates.example.com/appcast.xml",
            publicKey: "public-key"
        ))
        XCTAssertFalse(UpdateController.hasValidConfiguration(
            feedURL: "http://updates.example.com/appcast.xml",
            publicKey: "public-key"
        ))
        XCTAssertFalse(UpdateController.hasValidConfiguration(
            feedURL: "https://updates.example.com/appcast.xml",
            publicKey: "  "
        ))
    }
}
