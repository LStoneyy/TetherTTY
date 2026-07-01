import XCTest
@testable import TetherTTY

@MainActor
final class AppLockViewModelTests: XCTestCase {
    func testSuccessfulUnlockExposesHostListBoundary() async {
        let viewModel = AppLockViewModel(unlockClient: StubVaultUnlockClient(result: .unlocked))

        await viewModel.unlock()

        XCTAssertEqual(viewModel.lockState, .unlocked)
        XCTAssertFalse(viewModel.isAuthenticating)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeniedUnlockKeepsVaultLocked() async {
        let viewModel = AppLockViewModel(unlockClient: StubVaultUnlockClient(result: .denied("Canceled")))

        await viewModel.unlock()

        XCTAssertEqual(viewModel.lockState, .locked)
        XCTAssertFalse(viewModel.isAuthenticating)
        XCTAssertEqual(viewModel.errorMessage, "Canceled")
    }

    func testUnavailableAuthenticationKeepsVaultLocked() async {
        let viewModel = AppLockViewModel(unlockClient: StubVaultUnlockClient(result: .unavailable("Unavailable")))

        await viewModel.unlock()

        XCTAssertEqual(viewModel.lockState, .locked)
        XCTAssertEqual(viewModel.errorMessage, "Unavailable")
    }
}
