import Foundation
import SwiftUI

@MainActor
final class AppLockViewModel: ObservableObject {
    @Published private(set) var lockState: AppLockState = .locked
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    /// A full-screen cover that hides app content (terminal output, host lists, the connection
    /// editor) from the app-switcher snapshot and from anyone glancing at the screen while the
    /// app is momentarily inactive/backgrounded. Shown while unlocked and not showing the
    /// re-lock shield.
    @Published private(set) var isPrivacyCoverVisible = false

    /// Set once the app has spent `relockTimeout` or more seconds in the background. The
    /// existing unlocked content stays alive underneath; the shield window shows the lock UI
    /// (instead of the plain privacy cover) until authentication succeeds again.
    @Published private(set) var isRelockRequired = false

    /// Whether the shield window should be visible at all, regardless of which content it shows.
    var isShieldVisible: Bool { isPrivacyCoverVisible || isRelockRequired }

    /// The single automatic re-authentication attempt started when a re-lock is triggered.
    /// Exposed so callers (and tests) can `await pendingReauthentication?.value` to observe its
    /// completion deterministically instead of racing the main-actor queue.
    private(set) var pendingReauthentication: Task<Void, Never>?

    private let unlockClient: VaultUnlockClient
    private let relockTimeout: TimeInterval
    private let now: () -> Date

    /// Set when the scene enters `.background` (never `.inactive`) while unlocked; cleared after
    /// every `.active` evaluation so a stale timestamp can never cause a later relock.
    private var backgroundedAt: Date?

    init(
        unlockClient: VaultUnlockClient = LocalAuthenticationVaultUnlockClient(),
        relockTimeout: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.unlockClient = unlockClient
        self.relockTimeout = relockTimeout
        self.now = now
    }

    func unlock() async {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        errorMessage = nil

        let result = await unlockClient.unlock(reason: "Unlock TetherTTY to access saved SSH tethers.")
        isAuthenticating = false

        switch result {
        case .unlocked:
            lockState = .unlocked
            isRelockRequired = false
            isPrivacyCoverVisible = false
        case .unavailable(let message), .denied(let message):
            errorMessage = message
            // Only drop back to the cold-start locked screen if we were never unlocked in this
            // session. A denied/unavailable *re-lock* attempt must leave the existing content
            // (and `lockState == .unlocked`) alone — the re-lock shield stays up on its own.
            if lockState != .unlocked {
                lockState = .locked
            }
        }
    }

    /// Call with the SwiftUI `scenePhase` whenever it changes. Synchronous: all state (including
    /// `isPrivacyCoverVisible`/`isRelockRequired`) is updated immediately on the calling thread so
    /// a caller can show the shield window in the very same turn — critical for the cover to be
    /// up before the app-switcher snapshot is taken. If a re-lock is triggered, the single
    /// automatic authentication attempt is kicked off as a detached `Task` (see
    /// `pendingReauthentication`); it does not need to finish before this method returns.
    func scenePhaseDidChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            evaluateForegroundTransition()
        case .inactive:
            if lockState == .unlocked && !isRelockRequired {
                isPrivacyCoverVisible = true
            }
        case .background:
            if lockState == .unlocked {
                // Idempotent: a duplicate `.background` call within the same background cycle
                // (e.g. a redundant notification) must not push the timestamp later, or a
                // shorter apparent elapsed time could wrongly suppress a due relock.
                if backgroundedAt == nil {
                    backgroundedAt = now()
                }
                if !isRelockRequired {
                    isPrivacyCoverVisible = true
                }
            }
        @unknown default:
            break
        }
    }

    private func evaluateForegroundTransition() {
        isPrivacyCoverVisible = false

        guard lockState == .unlocked, let backgroundedAt else {
            backgroundedAt = nil
            return
        }
        self.backgroundedAt = nil

        guard !isRelockRequired else { return }

        let elapsed = now().timeIntervalSince(backgroundedAt)
        guard elapsed >= relockTimeout else { return }

        isRelockRequired = true
        errorMessage = nil
        pendingReauthentication = Task { [weak self] in
            await self?.unlock()
        }
    }
}
