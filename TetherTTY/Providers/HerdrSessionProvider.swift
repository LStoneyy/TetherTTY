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
        let requestConfig = SSHShellRequest(
            host: request.connection.host,
            port: request.connection.port,
            username: request.connection.username,
            password: request.password
        )

        let commands = [
            "herdr list",
            "herdr status"
        ]

        var allSessions: [TerminalSession] = []
        for cmd in commands {
            do {
                let output = try await sshClient.execute(requestConfig, command: cmd)
                let sessions = HerdrSessionParser.parse(output)
                if !sessions.isEmpty {
                    allSessions.append(contentsOf: sessions)
                    break
                }
            } catch {
                continue
            }
        }

        return allSessions
    }
}
