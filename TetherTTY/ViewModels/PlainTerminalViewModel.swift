import Foundation
import SwiftTerm

@MainActor
final class PlainTerminalViewModel: ObservableObject {
    @Published private(set) var state: TerminalConnectionState = .idle
    @Published private(set) var session: SSHSession?

    private let request: TerminalConnectionRequest
    private let sshClient: SSHClient
    private var connectedSession: SSHSession?
    private let reconnectGrace: TimeInterval
    private let maxReattachAttempts: Int
    private let reattemptBackoff: TimeInterval
    private var backgroundedAt: Date?

    let terminal = SSHTerminalView(frame: .zero)

    init(
        request: TerminalConnectionRequest,
        sshClient: SSHClient = SwiftNIOSSHClient(),
        reconnectGrace: TimeInterval = 2,
        maxReattachAttempts: Int = 3,
        reattemptBackoff: TimeInterval = 1
    ) {
        self.request = request
        self.sshClient = sshClient
        self.reconnectGrace = reconnectGrace
        self.maxReattachAttempts = maxReattachAttempts
        self.reattemptBackoff = reattemptBackoff

        terminal.onSend = { [weak self] bytes in
            self?.sendBytes(bytes)
        }
    }

    func connect() async {
        guard state != .terminalOpen else { return }

        state = .connecting

        do {
            try await Task.sleep(nanoseconds: 120_000_000)
            state = .authenticating
            try await openAndWireShell()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func openAndWireShell() async throws {
        var shell = try await sshClient.openShell(
            SSHShellRequest(
                host: request.connection.host,
                port: request.connection.port,
                username: request.connection.username,
                password: request.password
            )
        )

        if state == .disconnected {
            await shell.disconnect()
            return
        }

        shell.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.state = .disconnected
            }
        }

        connectedSession = shell
        session = shell
        wireSessionOutput(shell)
        state = .terminalOpen

        // Rendering the startup action to an actual shell command string happens
        // exactly once, here, at the SSH boundary. If validation fails, nothing
        // is sent (never a partial/broken command).
        if let startupCommand = request.startupAction?.renderStartupCommand() {
            try? await shell.send(Array((startupCommand + "\n").utf8))
        }
    }

    func applicationDidEnterBackground() {
        backgroundedAt = Date()
    }

    func applicationWillEnterForeground() async {
        guard let backgroundedAt else { return }
        let elapsed = Date().timeIntervalSince(backgroundedAt)
        self.backgroundedAt = nil

        switch state {
        case .terminalOpen where elapsed < reconnectGrace:
            return                       // brief background: assume socket survived
        case .terminalOpen, .disconnected, .failed:
            await reattach()
        default:
            return                       // .idle/.connecting/.authenticating/.reconnecting: leave in-flight work alone
        }
    }

    private func reattach() async {
        // CRITICAL: detach the stale session's callbacks BEFORE disconnecting it,
        // otherwise its delayed onDisconnect fires later and clobbers our state back to .disconnected.
        if var old = connectedSession {
            old.onOutput = nil
            old.onDisconnect = nil
            await old.disconnect()
        }
        connectedSession = nil
        session = nil
        state = .reconnecting

        let attempts = max(1, maxReattachAttempts)
        for attemptIndex in 0..<attempts {
            do {
                try await openAndWireShell()
                return   // success: openAndWireShell set state to .terminalOpen
            } catch {
                guard attemptIndex < attempts - 1 else { break }
                let delay = reattemptBackoff * pow(2, Double(attemptIndex))
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                // remain in .reconnecting for the next attempt
            }
        }

        // All attempts exhausted: fall back to the manual reconnect UI (.disconnected footer).
        state = .disconnected
    }

    private func wireSessionOutput(_ session: SSHSession) {
        var session = session
        session.onOutput = { [weak terminal] bytes in
            terminal?.feedOutput(bytes)
        }
        terminal.onSizeChanged = { [weak self] cols, rows in
            Task { @MainActor in
                await self?.connectedSession?.resize(cols: cols, rows: rows)
            }
        }
        let current = terminal.getTerminal()
        if current.cols > 0, current.rows > 0 {
            Task { @MainActor in
                await session.resize(cols: current.cols, rows: current.rows)
            }
        }
    }

    func sendBytes(_ bytes: [UInt8]) {
        guard let session = connectedSession else { return }
        Task {
            try? await session.send(bytes)
        }
    }

    func disconnect() async {
        await connectedSession?.disconnect()
        connectedSession = nil
        session = nil
        state = .disconnected
    }

    func makeReconnectRequest() -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: request.connection,
            password: request.password,
            startupAction: nil
        )
    }

    var connectionRequest: TerminalConnectionRequest { request }
}

