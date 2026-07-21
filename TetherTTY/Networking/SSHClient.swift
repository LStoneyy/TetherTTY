import Foundation

struct SSHShellRequest: Equatable {
    let host: String
    let port: Int
    let username: String
    let password: String
}

protocol SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession
}

protocol SSHSession {
    var banner: String { get }
    func send(_ input: String) async throws -> String
    func disconnect() async
}

enum SSHClientError: LocalizedError, Equatable {
    case missingPassword
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            "This tether has no stored password. Edit the connection and save a password before connecting."
        case .connectionFailed(let message):
            message
        }
    }
}

struct SimulatedSSHClient: SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        try await Task.sleep(nanoseconds: 250_000_000)

        guard !request.password.isEmpty else {
            throw SSHClientError.missingPassword
        }

        return SimulatedSSHSession(request: request)
    }
}

final class SimulatedSSHSession: SSHSession {
    let banner: String
    private let prompt: String

    init(request: SSHShellRequest) {
        prompt = "\(request.username)@\(request.host)$"
        banner = "Connected to \(request.username)@\(request.host):\(request.port)\n\(prompt) "
    }

    func send(_ input: String) async throws -> String {
        try await Task.sleep(nanoseconds: 80_000_000)
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if command == "clear" {
            return "\(prompt) "
        }

        return "\(command)\n(simulated ssh shell) command accepted\n\(prompt) "
    }

    func disconnect() async {}
}
