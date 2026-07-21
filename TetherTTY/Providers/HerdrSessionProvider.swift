import Foundation

protocol HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> ([TerminalSession], diagnostic: String?)
}

struct SimulatedHerdrSessionProvider: HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> ([TerminalSession], diagnostic: String?) {
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
        ], nil)
    }
}

struct RealHerdrSessionProvider: HerdrSessionProvider {
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
            command: "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" herdr session list --json"
        )
        print("[Herdr] raw output: \(result.stdout)")
        print("[Herdr] stderr: \(result.stderr), exit: \(result.exitStatus)")
        let sessions = HerdrSessionParser.parse(result.stdout)
        let diagnostic: String? = {
            if result.exitStatus != 0 {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "herdr exited \(result.exitStatus)" : trimmed
            }
            if sessions.isEmpty && !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }()
        return (sessions, diagnostic)
    }
}
