import XCTest
@testable import TetherTTY

final class TmuxSessionParserTests: XCTestCase {
    func testParsesRepresentativeOutput() {
        let output = """
        shell\t2\t1\t1699000000
        editor\t3\t0\t1698996400
        """

        let sessions = TmuxSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].displayName, "shell")
        XCTAssertEqual(sessions[0].detail, "2 windows, 1 attached")
        if case .tmux(let name, let windows, let attached, let created) = sessions[0].provider {
            XCTAssertEqual(name, "shell")
            XCTAssertEqual(windows, 2)
            XCTAssertEqual(attached, 1)
            XCTAssertNotNil(created)
            XCTAssertEqual(created?.timeIntervalSince1970, 1_699_000_000)
        } else {
            XCTFail("Expected tmux session")
        }

        XCTAssertEqual(sessions[1].displayName, "editor")
        if case .tmux(_, let windows, let attached, _) = sessions[1].provider {
            XCTAssertEqual(windows, 3)
            XCTAssertEqual(attached, 0)
        } else {
            XCTFail("Expected tmux session")
        }
    }

    func testParsesEmptyOutput() {
        let sessions = TmuxSessionParser.parse("")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParsesWhitespaceOnlyOutput() {
        let sessions = TmuxSessionParser.parse("   \n  \n  ")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSkipsMalformedRows() {
        let output = """
        valid\t2\t1\t1699000000
        not-enough-columns
        \t0\t0\t0
        valid2\t5\t2\t1699000001
        """

        let sessions = TmuxSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].displayName, "valid")
        XCTAssertEqual(sessions[1].displayName, "valid2")
    }

    func testParsesNonNumericWindowCountDefaultsToZero() {
        let output = "session\tfoo\t1\t1699000000"

        let sessions = TmuxSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 1)
        if case .tmux(_, let windows, let attached, _) = sessions[0].provider {
            XCTAssertEqual(windows, 0)
            XCTAssertEqual(attached, 1)
        } else {
            XCTFail("Expected tmux session")
        }
    }

    func testParsesInvalidTimestampAsNil() {
        let output = "session\t2\t1\tnot-a-timestamp"

        let sessions = TmuxSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 1)
        if case .tmux(_, _, _, let created) = sessions[0].provider {
            XCTAssertNil(created)
        } else {
            XCTFail("Expected tmux session")
        }
    }

    func testStartupCommandForTmuxSession() {
        let session = TerminalSession(
            id: "work",
            provider: .tmux(name: "work", windowCount: 3, attachedCount: 0, created: nil),
            displayName: "work",
            detail: "3 windows, 0 attached"
        )

        XCTAssertEqual(session.startupAction?.renderStartupCommand(), "tmux attach-session -t 'work'")
    }

    func testStartupCommandForPlainShell() {
        XCTAssertNil(TerminalSession.plainShellSession.startupAction)
    }
}
