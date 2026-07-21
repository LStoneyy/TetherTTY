import Foundation

@MainActor
final class PlainTerminalViewModel: ObservableObject {
    @Published private(set) var state: TerminalConnectionState = .idle
    @Published private(set) var transcript = ""
    @Published var input = ""

    private let request: TerminalConnectionRequest
    private let sshClient: SSHClient
    private var session: SSHSession?

    init(request: TerminalConnectionRequest, sshClient: SSHClient = SwiftNIOSSHClient()) {
        self.request = request
        self.sshClient = sshClient
    }

    func connect() async {
        guard state != .terminalOpen else { return }

        state = .connecting

        do {
            try await Task.sleep(nanoseconds: 120_000_000)
            state = .authenticating

            let shell = try await sshClient.openShell(
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

            session = shell
            transcript = shell.banner
            state = .terminalOpen

            if let startupCommand = request.startupCommand {
                await sendCommand(startupCommand)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendCurrentInput() async {
        guard state != .disconnected else { return }

        let command = input
        input = ""

        guard let session else {
            state = .failed("No active terminal session.")
            return
        }

        do {
            transcript += command
            transcript += "\n"
            transcript += try await session.send(command)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendSpecialKey(_ key: TerminalSpecialKey) {
        input += key.sequence
    }

    private func sendCommand(_ command: String) async {
        guard state != .disconnected else { return }
        guard let session else {
            state = .failed("No active terminal session.")
            return
        }

        do {
            transcript += command
            transcript += "\n"
            transcript += try await session.send(command)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await session?.disconnect()
        session = nil
        state = .disconnected
        transcript += "\n[disconnected]\n"
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

enum TerminalSpecialKey: String, CaseIterable, Identifiable {
    case esc = "Esc"
    case ctrl = "Ctrl"
    case tab = "Tab"
    case up = "↑"
    case down = "↓"
    case pipe = "|"
    case tilde = "~"
    case slash = "/"

    var id: String { rawValue }

    var sequence: String {
        switch self {
        case .esc: "\u{1B}"
        case .ctrl: "^"
        case .tab: "\t"
        case .up: "\u{1B}[A"
        case .down: "\u{1B}[B"
        case .pipe: "|"
        case .tilde: "~"
        case .slash: "/"
        }
    }
}
