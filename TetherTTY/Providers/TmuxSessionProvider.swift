import Foundation

protocol TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> ([TerminalSession], diagnostic: String?)
}

struct SimulatedTmuxSessionProvider: TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> ([TerminalSession], diagnostic: String?) {
        try await Task.sleep(nanoseconds: 500_000_000)
        let now = Date()
        return ([
            TerminalSession(
                id: "shell",
                provider: .tmux(
                    name: "shell",
                    windowCount: 2,
                    attachedCount: 1,
                    created: now.addingTimeInterval(-86400)
                ),
                displayName: "shell",
                detail: "2 windows, 1 attached"
            ),
            TerminalSession(
                id: "editor",
                provider: .tmux(
                    name: "editor",
                    windowCount: 3,
                    attachedCount: 0,
                    created: now.addingTimeInterval(-3600)
                ),
                displayName: "editor",
                detail: "3 windows, 0 attached"
            ),
        ], nil)
    }
}

struct RealTmuxSessionProvider: TmuxSessionProvider {
    let sshClient: SSHClient

    init(sshClient: SSHClient = SwiftNIOSSHClient()) {
        self.sshClient = sshClient
    }

    func fetchSessions(for request: TerminalConnectionRequest) async throws -> ([TerminalSession], diagnostic: String?) {
        let result = try await sshClient.execute(
            SSHShellRequest(
                host: request.connection.host,
                port: request.connection.port,
                username: request.connection.username,
                password: request.password
            ),
            command: "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" tmux list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}'"
        )
        print("[Tmux] raw output: \(result.stdout)")
        print("[Tmux] stderr: \(result.stderr), exit: \(result.exitStatus)")
        let sessions = TmuxSessionParser.parse(result.stdout)
        let diagnostic: String? = {
            if result.exitStatus != 0 {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "tmux exited \(result.exitStatus)" : trimmed
            }
            if sessions.isEmpty && !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }()
        return (sessions, diagnostic)
    }
}
