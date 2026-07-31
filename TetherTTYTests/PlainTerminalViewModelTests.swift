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

    func testForegroundAfterGraceReattaches() async {
        let session = StubSSHSession()
        let client = CountingSSHClient(session: session)
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "tmux attach-session -t work"),
            sshClient: client,
            reconnectGrace: 0
        )

        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(client.openShellCallCount, 1)

        viewModel.applicationDidEnterBackground()
        await viewModel.applicationWillEnterForeground()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.openShellCallCount, 2)
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(session.sentBytes, Array("tmux attach-session -t work\n".utf8))
    }

    func testBriefForegroundWithinGraceDoesNotReattach() async {
        let session = StubSSHSession()
        let client = CountingSSHClient(session: session)
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: client,
            reconnectGrace: 1000
        )

        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(client.openShellCallCount, 1)

        viewModel.applicationDidEnterBackground()
        await viewModel.applicationWillEnterForeground()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.openShellCallCount, 1)
        XCTAssertEqual(viewModel.state, .terminalOpen)
    }

    func testForegroundWhileDisconnectedReattaches() async {
        let session = StubSSHSession()
        let client = CountingSSHClient(session: session)
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: client,
            reconnectGrace: 0
        )

        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(client.openShellCallCount, 1)

        session.onDisconnect?()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.state, .disconnected)

        viewModel.applicationDidEnterBackground()
        await viewModel.applicationWillEnterForeground()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.openShellCallCount, 2)
        XCTAssertEqual(viewModel.state, .terminalOpen)
    }

    func testReattachSucceedsOnSecondAttempt() async {
        let session = StubSSHSession()
        let client = FlakySSHClient(session: session)
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(startupCommand: "tmux attach-session -t work"),
            sshClient: client,
            reconnectGrace: 0,
            maxReattachAttempts: 3,
            reattemptBackoff: 0
        )

        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(client.openShellCallCount, 1)

        // Next reattach fails once, then succeeds.
        client.failuresRemaining = 1
        viewModel.applicationDidEnterBackground()
        await viewModel.applicationWillEnterForeground()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.openShellCallCount, 3)   // 1 initial + 1 failed + 1 successful
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(session.sentBytes, Array("tmux attach-session -t work\n".utf8))
    }

    func testReattachExhaustsToDisconnected() async {
        let session = StubSSHSession()
        let client = FlakySSHClient(session: session)
        let viewModel = PlainTerminalViewModel(
            request: terminalRequest(),
            sshClient: client,
            reconnectGrace: 0,
            maxReattachAttempts: 2,
            reattemptBackoff: 0
        )

        await viewModel.connect()
        XCTAssertEqual(viewModel.state, .terminalOpen)
        XCTAssertEqual(client.openShellCallCount, 1)

        // Fail more times than maxReattachAttempts.
        client.failuresRemaining = 5
        viewModel.applicationDidEnterBackground()
        await viewModel.applicationWillEnterForeground()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.state, .disconnected)
        XCTAssertEqual(client.openShellCallCount, 3)   // 1 initial + 2 reattach attempts
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

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
        SSHExecResult(stdout: "stub output for: \(command)\n", stderr: "", exitStatus: 0)
    }
}

final class CountingSSHClient: SSHClient {
    private(set) var openShellCallCount = 0
    let session: SSHSession

    init(session: SSHSession) {
        self.session = session
    }

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        openShellCallCount += 1
        return session
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
        SSHExecResult(stdout: "", stderr: "", exitStatus: 0)
    }
}

final class FlakySSHClient: SSHClient {
    private(set) var openShellCallCount = 0
    var failuresRemaining = 0
    let session: SSHSession

    init(session: SSHSession) {
        self.session = session
    }

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        openShellCallCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SSHClientError.connectionFailed("transient")
        }
        return session
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
        SSHExecResult(stdout: "", stderr: "", exitStatus: 0)
    }
}

private struct FailingSSHClient: SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        throw SSHClientError.connectionFailed("No route to host")
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
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
