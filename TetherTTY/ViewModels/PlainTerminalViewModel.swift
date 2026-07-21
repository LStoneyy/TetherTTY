import Foundation

@MainActor
final class PlainTerminalViewModel: ObservableObject {
    @Published private(set) var state: TerminalConnectionState = .idle
    @Published private(set) var session: SSHSession?

    private let request: TerminalConnectionRequest
    private let sshClient: SSHClient
    private var connectedSession: SSHSession?

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
            state = .terminalOpen

            if let startupCommand = request.startupCommand {
                try? await shell.send(Array((startupCommand + "\n").utf8))
            }
        } catch {
            state = .failed(error.localizedDescription)
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

enum TerminalSpecialKey: String, CaseIterable, Identifiable {
    case esc = "Esc"
    case ctrl = "Ctrl"
    case tab = "Tab"
    case up = "\u{2191}"
    case down = "\u{2193}"
    case pipe = "|"
    case tilde = "~"
    case slash = "/"

    var id: String { rawValue }

    var bytes: [UInt8] {
        switch self {
        case .esc: [0x1B]
        case .ctrl: [] // modifier — handled by CtrlState in view
        case .tab: [0x09]
        case .up: [0x1B, 0x5B, 0x41]
        case .down: [0x1B, 0x5B, 0x42]
        case .pipe: [0x7C]
        case .tilde: [0x7E]
        case .slash: [0x2F]
        }
    }
}
