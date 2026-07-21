import Foundation

protocol HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> [TerminalSession]
}

struct SimulatedHerdrSessionProvider: HerdrSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> [TerminalSession] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return [
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
        ]
    }
}

struct RealHerdrSessionProvider: HerdrSessionProvider {
    let sshClient: SSHClient

    init(sshClient: SSHClient = SwiftNIOSSHClient()) {
        self.sshClient = sshClient
    }

    func fetchSessions(for request: TerminalConnectionRequest) async throws -> [TerminalSession] {
        let output = try await sshClient.execute(
            SSHShellRequest(
                host: request.connection.host,
                port: request.connection.port,
                username: request.connection.username,
                password: request.password
            ),
            command: "herdr session list --json"
        )
        print("[Herdr] raw output: \(output)")
        return HerdrSessionParser.parse(output)
    }
}
