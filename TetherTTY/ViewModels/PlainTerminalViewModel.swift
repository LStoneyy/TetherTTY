import Foundation
import SwiftTerm

@MainActor
final class PlainTerminalViewModel: ObservableObject {
    @Published private(set) var state: TerminalConnectionState = .idle
    @Published private(set) var session: SSHSession?

    private let request: TerminalConnectionRequest
    private let sshClient: SSHClient
    private var connectedSession: SSHSession?

    let terminal = SSHTerminalView(frame: .zero)

    init(request: TerminalConnectionRequest, sshClient: SSHClient = SwiftNIOSSHClient()) {
        self.request = request
        self.sshClient = sshClient

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

            if let startupCommand = request.startupCommand {
                try? await shell.send(Array((startupCommand + "\n").utf8))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func wireSessionOutput(_ session: SSHSession) {
        var session = session
        session.onOutput = { [weak terminal] bytes in
            terminal?.feed(byteArray: ArraySlice(bytes))
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
            startupCommand: nil
        )
    }

    var connectionRequest: TerminalConnectionRequest { request }
}

