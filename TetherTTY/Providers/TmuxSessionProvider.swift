import Foundation

protocol TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome)
}

#if DEBUG
struct SimulatedTmuxSessionProvider: TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome) {
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
        ], .ok)
    }
}
#endif

struct RealTmuxSessionProvider: TmuxSessionProvider {
    /// `-u` makes tmux treat the client as UTF-8 regardless of the remote locale. Without it,
    /// a non-interactive SSH exec on a server with no UTF-8 `LANG`/`LC_*` (common on minimal
    /// Linux hosts) makes tmux replace the tab separators below (and any non-ASCII characters
    /// in session names) with `_`, so `TmuxSessionParser` would find no sessions at all.
    static let listSessionsCommand =
        "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" tmux -u list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}'"

    let sshClient: SSHClient

    init(sshClient: SSHClient = SwiftNIOSSHClient()) {
        self.sshClient = sshClient
    }

    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome) {
        let result = try await sshClient.execute(
            SSHShellRequest(
                host: request.connection.host,
                port: request.connection.port,
                username: request.connection.username,
                password: request.password
            ),
            command: Self.listSessionsCommand
        )
        let sessions = TmuxSessionParser.parse(result.stdout)
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .tmux,
            exitStatus: result.exitStatus,
            stderr: result.stderr,
            sessionCount: sessions.count
        )
        return (sessions, outcome)
    }
}
