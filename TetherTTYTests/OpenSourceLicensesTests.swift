import XCTest
@testable import TetherTTY

/// These tests run in the TetherTTYTests target, which is hosted inside the TetherTTY.app process
/// (see `TEST_HOST`/`BUNDLE_LOADER` in the test target's build settings), so `Bundle.main` here is
/// the app bundle the license resources are actually copied into — the same bundle `AboutView`
/// reads from at runtime.
final class OpenSourceLicensesTests: XCTestCase {
    func testEveryListedLicenseResourceLoadsNonEmpty() {
        for license in OpenSourceLicenses.all {
            let text = OpenSourceLicenses.text(forResource: license.resourceName)
            XCTAssertNotNil(text, "Expected a bundled license resource for \(license.resourceName)")
            XCTAssertFalse(
                text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                "Expected non-empty license text for \(license.resourceName)"
            )
        }
    }

    func testTetherTTYLicenseMentionsApache() {
        let text = OpenSourceLicenses.text(forResource: "TetherTTY")
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Apache License") ?? false)
    }

    func testMissingResourceReturnsNil() {
        XCTAssertNil(OpenSourceLicenses.text(forResource: "definitely-not-a-real-license"))
    }
}
