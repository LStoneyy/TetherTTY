import SwiftUI
import XCTest
@testable import TetherTTY

final class AbyssalThemeTests: XCTestCase {
    func testHostStatusUsesDistinctSemanticTints() {
        XCTAssertNotEqual(HostStatus.unknown.tint, HostStatus.reachable.tint)
        XCTAssertNotEqual(HostStatus.warning.tint, HostStatus.failed.tint)
    }

    func testHostSummaryDefaultsToUnknownAndNotFavorite() {
        let host = HostSummary(alias: "Lair", address: "192.0.2.10")

        XCTAssertEqual(host.alias, "Lair")
        XCTAssertEqual(host.address, "192.0.2.10")
        XCTAssertEqual(host.status, .unknown)
        XCTAssertFalse(host.isFavorite)
    }
}
