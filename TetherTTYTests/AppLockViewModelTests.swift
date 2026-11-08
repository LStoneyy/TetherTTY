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

    // MARK: - Privacy cover / re-lock

    func testColdStartDoesNotShowPrivacyCoverWhileLocked() {
        let viewModel = AppLockViewModel(unlockClient: StubVaultUnlockClient(result: .unlocked))

        XCTAssertEqual(viewModel.lockState, .locked)

        viewModel.scenePhaseDidChange(to: .inactive)
        XCTAssertFalse(viewModel.isPrivacyCoverVisible)
        XCTAssertFalse(viewModel.isShieldVisible)

        viewModel.scenePhaseDidChange(to: .background)
        XCTAssertFalse(viewModel.isPrivacyCoverVisible)
        XCTAssertFalse(viewModel.isShieldVisible)
    }

    func testInactiveWithoutBackgroundShowsAndHidesCoverWithNoRelock() async {
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(unlockClient: client)
        await viewModel.unlock()
        XCTAssertEqual(viewModel.lockState, .unlocked)

        viewModel.scenePhaseDidChange(to: .inactive)
        XCTAssertTrue(viewModel.isPrivacyCoverVisible)
        XCTAssertFalse(viewModel.isRelockRequired)

        viewModel.scenePhaseDidChange(to: .active)
        XCTAssertFalse(viewModel.isPrivacyCoverVisible)
        XCTAssertFalse(viewModel.isRelockRequired)
        XCTAssertFalse(viewModel.isShieldVisible)
        XCTAssertNil(viewModel.pendingReauthentication, "No automatic re-lock attempt should have been scheduled")
        XCTAssertEqual(client.unlockCallCount, 1, "Only the initial manual unlock() call, no automatic re-lock attempt")
    }

    func testBackgroundUnderTimeoutDoesNotRelock() async {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(
            unlockClient: client,
            relockTimeout: 300,
            now: { currentDate }
        )
        await viewModel.unlock()
        XCTAssertEqual(client.unlockCallCount, 1)

        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background)
        viewModel.scenePhaseDidChange(to: .inactive)

        currentDate = currentDate.addingTimeInterval(299)
        viewModel.scenePhaseDidChange(to: .active)

        XCTAssertFalse(viewModel.isRelockRequired)
        XCTAssertFalse(viewModel.isPrivacyCoverVisible)
        XCTAssertFalse(viewModel.isShieldVisible)
        XCTAssertNil(viewModel.pendingReauthentication)
        XCTAssertEqual(client.unlockCallCount, 1, "No automatic re-lock attempt should have been started")
    }

    func testBackgroundAtTimeoutTriggersExactlyOneAutomaticUnlockAttempt() async {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(
            unlockClient: client,
            relockTimeout: 300,
            now: { currentDate }
        )
        await viewModel.unlock()
        XCTAssertEqual(client.unlockCallCount, 1)

        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background)
        viewModel.scenePhaseDidChange(to: .inactive)

        currentDate = currentDate.addingTimeInterval(300)
        viewModel.scenePhaseDidChange(to: .active)

        // The shield must go up synchronously, before the automatic re-auth attempt resolves.
        XCTAssertTrue(viewModel.isRelockRequired)
        XCTAssertNotNil(viewModel.pendingReauthentication)

        await viewModel.pendingReauthentication?.value

        // Successful automatic re-auth clears the shield and keeps the content unlocked.
        XCTAssertFalse(viewModel.isRelockRequired)
        XCTAssertFalse(viewModel.isShieldVisible)
        XCTAssertEqual(viewModel.lockState, .unlocked)
        XCTAssertEqual(client.unlockCallCount, 2, "Exactly one automatic re-lock auth attempt should have fired")
    }

    func testDeniedRelockStaysShieldedWithErrorAndDoesNotRetryOnFaceIDStyleInactiveActive() async {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(
            unlockClient: client,
            relockTimeout: 300,
            now: { currentDate }
        )
        await viewModel.unlock()

        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background)
        viewModel.scenePhaseDidChange(to: .inactive)

        currentDate = currentDate.addingTimeInterval(300)
        client.result = .denied("Canceled")
        viewModel.scenePhaseDidChange(to: .active)
        await viewModel.pendingReauthentication?.value

        XCTAssertTrue(viewModel.isRelockRequired)
        XCTAssertTrue(viewModel.isShieldVisible)
        XCTAssertEqual(viewModel.lockState, .unlocked, "Existing content must stay alive underneath the shield")
        XCTAssertEqual(viewModel.errorMessage, "Canceled")
        XCTAssertEqual(client.unlockCallCount, 2)

        // Face ID prompt-style transition: active -> inactive -> active, with no intervening
        // `.background`. Must not start another automatic auth attempt or loop.
        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .active)

        XCTAssertTrue(viewModel.isRelockRequired)
        XCTAssertEqual(viewModel.errorMessage, "Canceled")
        XCTAssertEqual(client.unlockCallCount, 2, "No additional automatic auth attempt should have been started")

        // The user can still retry manually via the Unlock button.
        client.result = .unlocked
        await viewModel.unlock()
        XCTAssertFalse(viewModel.isRelockRequired)
        XCTAssertFalse(viewModel.isShieldVisible)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBackgroundTimestampIsClearedAfterEvaluation() async {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(
            unlockClient: client,
            relockTimeout: 300,
            now: { currentDate }
        )
        await viewModel.unlock()

        // First background cycle: long enough to relock, and the auto re-auth succeeds.
        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background)
        currentDate = currentDate.addingTimeInterval(300)
        viewModel.scenePhaseDidChange(to: .active)
        await viewModel.pendingReauthentication?.value
        XCTAssertEqual(client.unlockCallCount, 2)
        XCTAssertFalse(viewModel.isRelockRequired)

        // Second, short background cycle: if the first timestamp were not cleared, a naive
        // implementation could still compute a stale (too-large) elapsed time here. It must not.
        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background)
        currentDate = currentDate.addingTimeInterval(5)
        viewModel.scenePhaseDidChange(to: .active)

        XCTAssertFalse(viewModel.isRelockRequired)
        XCTAssertFalse(viewModel.isShieldVisible)
        XCTAssertEqual(client.unlockCallCount, 2, "Short second background cycle must not trigger another re-lock")
    }

    func testDuplicateBackgroundCallDoesNotOverwriteFirstBackgroundedTimestamp() async {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let client = CountingVaultUnlockClient(result: .unlocked)
        let viewModel = AppLockViewModel(
            unlockClient: client,
            relockTimeout: 300,
            now: { currentDate }
        )
        await viewModel.unlock()

        viewModel.scenePhaseDidChange(to: .inactive)
        viewModel.scenePhaseDidChange(to: .background) // first background call: records t0

        currentDate = currentDate.addingTimeInterval(250)
        // Duplicate `.background` call (e.g. a redundant UIKit scene notification) later in the
        // same cycle: must NOT push the recorded timestamp forward to t0+250.
        viewModel.scenePhaseDidChange(to: .background)
        viewModel.scenePhaseDidChange(to: .inactive)

        currentDate = currentDate.addingTimeInterval(55) // elapsed since t0 == 305s; since the duplicate == 55s
        viewModel.scenePhaseDidChange(to: .active)

        XCTAssertTrue(
            viewModel.isRelockRequired,
            "Elapsed time must be measured from the FIRST background call (305s), not the duplicate (55s)"
        )
        XCTAssertNotNil(viewModel.pendingReauthentication)
        await viewModel.pendingReauthentication?.value
        XCTAssertEqual(client.unlockCallCount, 2)
    }
}

/// A `VaultUnlockClient` stub that counts how many times `unlock(reason:)` was invoked, so tests
/// can assert that automatic re-lock authentication fires exactly once per trigger (and never in
/// a retry loop).
private final class CountingVaultUnlockClient: VaultUnlockClient {
    var result: VaultUnlockResult
    private(set) var unlockCallCount = 0

    init(result: VaultUnlockResult) {
        self.result = result
    }

    func unlock(reason: String) async -> VaultUnlockResult {
        unlockCallCount += 1
        return result
    }
}
