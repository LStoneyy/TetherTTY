import Foundation

protocol HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome)
}

#if DEBUG
struct SimulatedHerdrSessionProvider: HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome) {
        try await Task.sleep(nanoseconds: 500_000_000)
        return ([
            TerminalSession(
                id: "herdr-workspace-prod",
                provider: .herdr(
                    kind: "workspace",
                    name: "prod",
                    status: "active",
                    attachCommand: "herdr enter workspace prod",
                    metadata: "region:us-east-1"
                ),
                displayName: "prod",
                detail: "workspace · active · region:us-east-1"
            ),
            TerminalSession(
                id: "herdr-agent-builder",
                provider: .herdr(
                    kind: "agent",
                    name: "builder",
                    status: "idle",
                    attachCommand: "herdr attach agent builder",
                    metadata: nil
                ),
                displayName: "builder",
                detail: "agent · idle"
            ),
        ], .ok)
    }
}
#endif

struct RealHerdrSessionProvider: HerdrSessionProvider {
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
            command: "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" herdr session list --json"
        )
        let sessions = HerdrSessionParser.parse(result.stdout)
        let outcome = SessionDiscoveryClassifier.classify(
            tool: .herdr,
            exitStatus: result.exitStatus,
            stderr: result.stderr,
            sessionCount: sessions.count
        )
        return (sessions, outcome)
    }
}
