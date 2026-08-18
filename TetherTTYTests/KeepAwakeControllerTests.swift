import XCTest
@testable import TetherTTY

@MainActor
final class FakeIdleTimer: IdleTimerControlling {
    private(set) var writes: [Bool] = []

    func setIdleTimerDisabled(_ disabled: Bool) {
        writes.append(disabled)
    }
}

@MainActor
final class KeepAwakeControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "keep-awake-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshDefaultsAreDisabledAndUntouched() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(idleTimer.writes.isEmpty)
    }

    func testSetEnabledWithoutHoldDoesNotTouchTimerButPersists() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)

        controller.setEnabled(true)

        XCTAssertTrue(idleTimer.writes.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: KeepAwakeController.defaultStorageKey))
    }

    func testSetHoldingWhileEnabledWritesTrue() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)
        controller.setEnabled(true)

        controller.setHolding(true)

        XCTAssertEqual(idleTimer.writes, [true])
    }

    func testReleasingHoldWritesFalseAndKeepsPreference() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)
        controller.setEnabled(true)
        controller.setHolding(true)

        controller.setHolding(false)

        XCTAssertEqual(idleTimer.writes, [true, false])
        XCTAssertTrue(controller.isEnabled)
    }

    func testDisablingDuringHoldWritesFalseImmediately() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)
        controller.setEnabled(true)
        controller.setHolding(true)

        controller.setEnabled(false)

        XCTAssertEqual(idleTimer.writes, [true, false])
    }

    func testPreferencePersistsAcrossControllerInstances() {
        let firstIdleTimer = FakeIdleTimer()
        let first = KeepAwakeController(defaults: defaults, idleTimer: firstIdleTimer)
        first.setEnabled(true)

        let secondIdleTimer = FakeIdleTimer()
        let second = KeepAwakeController(defaults: defaults, idleTimer: secondIdleTimer)

        XCTAssertTrue(second.isEnabled)
    }

    func testRepeatedSetHoldingDoesNotDuplicateWrites() {
        let idleTimer = FakeIdleTimer()
        let controller = KeepAwakeController(defaults: defaults, idleTimer: idleTimer)
        controller.setEnabled(true)

        controller.setHolding(true)
        controller.setHolding(true)
        controller.setHolding(true)

        XCTAssertEqual(idleTimer.writes, [true])
    }
}
