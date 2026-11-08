import XCTest
@testable import TetherTTY

final class SessionDiscoveryClassifierTests: XCTestCase {
    func testExitStatus127IsNotInstalledForTmux() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 127,
            stderr: "sh: tmux: not found",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .notInstalled)
    }

    func testExitStatus127IsNotInstalledForHerdr() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .herdr,
            exitStatus: 127,
            stderr: "sh: herdr: not found",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .notInstalled)
    }

    func testTmuxNoServerRunningIsOkWithZeroSessions() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 1,
            stderr: "no server running on /tmp/tmux-501/default",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .ok)
    }

    func testTmuxErrorConnectingToIsOkWithZeroSessions() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 1,
            stderr: "error connecting to /tmp/tmux-501/default (No such file or directory)",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .ok)
    }

    func testTmuxNoServerRunningMatchIsCaseInsensitive() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 1,
            stderr: "No Server Running on /tmp/tmux-501/default",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .ok)
    }

    func testGenericFailureWithStderrBecomesDiagnostic() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 2,
            stderr: "unexpected tmux failure",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .diagnostic("unexpected tmux failure"))
    }

    func testGenericFailureWithoutStderrFallsBackToExitedMessage() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .herdr,
            exitStatus: 2,
            stderr: "   ",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .diagnostic("herdr exited 2"))
    }

    func testHerdrGenericFailureIsNotTreatedAsOk() {
        // The tmux-only "no server running" / "error connecting to" allowance must not leak
        // into herdr's classification.
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .herdr,
            exitStatus: 1,
            stderr: "no server running",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .diagnostic("no server running"))
    }

    func testSuccessWithEmptyStderrIsOk() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 0,
            stderr: "",
            sessionCount: 2
        )
        XCTAssertEqual(outcome, .ok)
    }

    func testSuccessWithSessionsAndStderrIsStillOk() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: 0,
            stderr: "some warning on stderr",
            sessionCount: 1
        )
        XCTAssertEqual(outcome, .ok)
    }

    func testSuccessWithNoSessionsAndStderrBecomesDiagnostic() {
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .herdr,
            exitStatus: 0,
            stderr: "warning: config file missing",
            sessionCount: 0
        )
        XCTAssertEqual(outcome, .diagnostic("warning: config file missing"))
    }
}
