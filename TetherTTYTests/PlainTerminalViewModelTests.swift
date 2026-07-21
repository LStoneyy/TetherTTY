import XCTest
@testable import TetherTTY

@MainActor
final class PlainTerminalViewModelTests: XCTestCase {
    func testConnectOpensTerminalAndShowsBanner() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        await viewModel.connect()

        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(viewModel.transcript, "stub banner\n")
    }

    func testSendCurrentInputAppendsCommandAndOutput() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: StubSSHSession())
        )
        await viewModel.connect()

        viewModel.input = "pwd"
        await viewModel.sendCurrentInput()

        XCTAssertTrue(viewModel.transcript.contains("pwd"))
        XCTAssertTrue(viewModel.transcript.contains("stub output for pwd"))
        XCTAssertEqual(viewModel.input, "")
    }

    func testSpecialKeyAddsTerminalSequenceToInput() {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        viewModel.sendSpecialKey(.tab)
        viewModel.sendSpecialKey(.pipe)

        XCTAssertEqual(viewModel.input, "\t|")
    }

    func testFailedConnectShowsFailureState() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: FailingSSHClient()
        )

        await viewModel.connect()

        XCTAssertEqual(viewModel.state, .failed("No route to host"))
    }

    func testStartupCommandSentAfterConnect() async {
        let session = StubSSHSession()
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "tmux attach-session -t work"),
            sshClient: StubSSHClient(session: session)
        )

        await viewModel.connect()

        XCTAssertTrue(viewModel.transcript.contains("tmux attach-session -t work"))
        XCTAssertTrue(viewModel.transcript.contains("stub output for tmux attach-session -t work"))
    }

    func testStartupCommandFailureShowsFailedState() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "explode"),
            sshClient: StubSSHClient(session: FailingSessionOnSend())
        )

        await viewModel.connect()

        XCTAssertEqual(viewModel.state, .failed("sending failed"))
    }

    private func terminalRequest(startupCommand: String? = nil) -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas"),
            password: "secret",
            startupCommand: startupCommand
        )
    }
}

private struct StubSSHClient: SSHClient {
    let session: SSHSession

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        session
    }
}

private struct FailingSSHClient: SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        throw SSHClientError.connectionFailed("No route to host")
    }
}

private final class StubSSHSession: SSHSession {
    let banner = "stub banner\n"

    func send(_ input: String) async throws -> String {
        "stub output for \(input)\n"
    }

    func disconnect() async {}
}

private final class FailingSessionOnSend: SSHSession {
    let banner = "failing banner\n"

    func send(_ input: String) async throws -> String {
        throw SSHClientError.connectionFailed("sending failed")
    }

    func disconnect() async {}
}
