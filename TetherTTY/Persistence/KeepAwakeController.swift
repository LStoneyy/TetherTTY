import Foundation
import UIKit

/// Testable seam over the single device flag we touch.
@MainActor
protocol IdleTimerControlling: AnyObject {
    func setIdleTimerDisabled(_ disabled: Bool)
}

@MainActor
final class UIApplicationIdleTimer: IdleTimerControlling {
    func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}

/// Owns the persisted "keep screen awake" preference and the device flag.
/// The flag is set exactly when the preference is on AND a terminal is currently
/// holding it. It is written only on a genuine value change.
@MainActor
final class KeepAwakeController {
    static let defaultStorageKey = "terminal.keep-awake.v1"

    private let defaults: UserDefaults
    private let idleTimer: IdleTimerControlling
    private let storageKey: String
    private var isHolding = false
    private var appliedValue = false

    private(set) var isEnabled: Bool

    // `idleTimer` defaults to `nil` (rather than `= UIApplicationIdleTimer()`) because default
    // parameter *values* are evaluated outside this initializer's actor context, and
    // `UIApplicationIdleTimer.init()` is itself `@MainActor`-isolated. Constructing it here in
    // the body runs within `init`'s own MainActor isolation instead.
    init(defaults: UserDefaults = .standard,
         idleTimer: IdleTimerControlling? = nil,
         storageKey: String = KeepAwakeController.defaultStorageKey) {
        self.defaults = defaults
        self.idleTimer = idleTimer ?? UIApplicationIdleTimer()
        self.storageKey = storageKey
        self.isEnabled = defaults.bool(forKey: storageKey)   // missing key -> false
    }

    @discardableResult
    func toggle() -> Bool { setEnabled(!isEnabled); return isEnabled }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: storageKey)
        reconcile()
    }

    /// Called by the terminal: is the active screen holding the timer open?
    func setHolding(_ holding: Bool) {
        isHolding = holding
        reconcile()
    }

    private func reconcile() {
        let desired = isEnabled && isHolding
        guard desired != appliedValue else { return }
        appliedValue = desired
        idleTimer.setIdleTimerDisabled(desired)
    }
}
