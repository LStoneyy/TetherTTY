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

    private func terminalRequest() -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas"),
            password: "secret"
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
