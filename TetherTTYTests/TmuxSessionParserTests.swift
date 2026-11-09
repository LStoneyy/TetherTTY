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

        XCTAssertEqual(session.startupAction?.renderStartupCommand(), "tmux -u attach-session -t 'work'")
    }

    func testStartupCommandForPlainShell() {
        XCTAssertNil(TerminalSession.plainShellSession.startupAction)
    }
    // MARK: - Discovery command (UTF-8 / locale regression)

    func testListSessionsCommandForcesUTF8AndUsesTabSeparators() {
        let command = RealTmuxSessionProvider.listSessionsCommand
        // Without `-u`, tmux on a host with no UTF-8 locale rewrites the tab separators to `_`
        // and discovery silently finds no sessions.
        XCTAssertTrue(command.contains("tmux -u list-sessions"))
        XCTAssertTrue(command.contains("#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}"))
    }

    func testProviderSendsListCommandAndParsesSessions() async throws {
        let client = RecordingExecSSHClient(
            result: SSHExecResult(stdout: "build\t1\t0\t1794221264\nlogs\t1\t0\t1794221264\n", stderr: "", exitStatus: 0)
        )
        let provider = RealTmuxSessionProvider(sshClient: client)
        let request = TerminalConnectionRequest(
            connection: Connection(alias: "Demo", host: "demo.local", username: "review"),
            password: "secret"
        )

        let (sessions, outcome) = try await provider.fetchSessions(for: request)

        XCTAssertEqual(client.commands, [RealTmuxSessionProvider.listSessionsCommand])
        XCTAssertEqual(sessions.map(\.displayName), ["build", "logs"])
        XCTAssertEqual(outcome, .ok)
    }

    func testLocaleMangledOutputYieldsNoSessions() {
        // Documents the failure mode `-u` prevents: tabs replaced by `_` are unparseable.
        XCTAssertTrue(TmuxSessionParser.parse("build_1_0_1794221264\n").isEmpty)
    }
}

private final class RecordingExecSSHClient: SSHClient {
    private(set) var commands: [String] = []
    let result: SSHExecResult

    init(result: SSHExecResult) {
        self.result = result
    }

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        throw CancellationError()
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
        commands.append(command)
        return result
    }
}

