import XCTest
@testable import TetherTTY

@MainActor
final class PlainTerminalViewModelTests: XCTestCase {
    func testConnectTransitionsStateToTerminalOpen() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        await viewModel.connect()

        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertNotNil(viewModel.session)
    }

    func testStartupCommandSentAsBytes() async {
        let session = StubSSHSession()
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "tmux attach-session -t work"),
            sshClient: StubSSHClient(session: session)
        )

        await viewModel.connect()

        let expected = Array("tmux attach-session -t work\n".utf8)
        XCTAssertEqual(session.sentBytes, expected)
    }

    func testFailedConnectShowsFailureState() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: FailingSSHClient()
        )

        await viewModel.connect()

        XCTAssertEqual(viewModel.state, .failed("No route to host"))
        XCTAssertNil(viewModel.session)
    }

    func testDisconnectSetsStateAndClearsSession() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: StubSSHSession())
        )
        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)

        await viewModel.disconnect()

        XCTAssertEqual(viewModel.state, .disconnected)
        XCTAssertNil(viewModel.session)
    }

    func testSendBytesForwardsToSession() async {
        let session = StubSSHSession()
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: session)
        )
        await viewModel.connect()

        viewModel.sendBytes([0x1B, 0x5B, 0x41])

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(session.sentBytes, [0x1B, 0x5B, 0x41])
    }

    func testReconnectRequestPreservesConnection() async {
        let original = terminalRequest()
        let viewModel = PlainTerminalViewModel(
            request: original,
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        let reconnectRequest = viewModel.makeReconnectRequest()

        XCTAssertEqual(reconnectRequest.connection.id, original.connection.id)
        XCTAssertEqual(reconnectRequest.password, original.password)
    }

    func testReconnectRequestHasNoStartupCommand() async {
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "tmux attach-session -t work"),
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        let reconnectRequest = viewModel.makeReconnectRequest()

        XCTAssertNil(reconnectRequest.startupCommand)
    }

    func testDisconnectCallbackSetsStateDisconnected() async {
        let session = StubSSHSession()
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: StubSSHClient(session: session)
        )
        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)

        session.onDisconnect?()

        // Wait for MainActor task to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.state, .disconnected)
    }

    private func terminalRequest(startupCommand: String? = nil) -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas"),
            password: "secret",
            startupCommand: startupCommand
        )
    }
}

struct StubSSHClient: SSHClient {
    let session: SSHSession

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        session
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> String {
        "stub output for: \(command)\n"
    }
}

private struct FailingSSHClient: SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        throw SSHClientError.connectionFailed("No route to host")
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> String {
        throw SSHClientError.connectionFailed("No route to host")
    }
}

final class StubSSHSession: SSHSession {
    var onOutput: (@Sendable ([UInt8]) -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    private(set) var sentBytes: [UInt8]?

    func send(_ bytes: [UInt8]) async throws {
        sentBytes = bytes
    }

    func resize(cols: Int, rows: Int) async {}

    func disconnect() async {}
}
