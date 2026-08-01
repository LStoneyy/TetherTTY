import Foundation

@MainActor
final class HostListViewModel: ObservableObject {
    @Published private(set) var connections: [Connection] = []
    @Published var errorMessage: String?
    @Published var hostKeyChallenge: HostKeyChallenge?

    /// User-facing progress of an in-flight connect attempt, driving the progress overlay. `nil`
    /// when no connect is being prepared.
    @Published var connectPhase: ConnectionPhase?

    /// Monotonic token used to invalidate a superseded/cancelled connect attempt: the async
    /// `terminalRequest` only applies its final state if its captured generation still matches.
    private var connectGeneration = 0

    private let repository: ConnectionRepository
    private let hostKeyTrustEvaluator: HostKeyTrustEvaluator
    private let knownHostStore: KnownHostStore

    init(
        repository: ConnectionRepository = LocalConnectionRepository(),
        hostKeyTrustEvaluator: HostKeyTrustEvaluator = HostKeyTrustEvaluator(),
        migrationDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.hostKeyTrustEvaluator = hostKeyTrustEvaluator
        self.knownHostStore = hostKeyTrustEvaluator.knownHostStore

        // One-time cleanup of legacy simulated known-host entries. The flag lives in an
        // injectable UserDefaults so tests can isolate it: a fresh install / fresh CI simulator
        // has this flag unset, which would otherwise wipe a test-injected known-host store on
        // first init and make host-key tests order-dependent.
        if !migrationDefaults.bool(forKey: "known-hosts-migrated-to-real-v1") {
            try? knownHostStore.clearAll()
            migrationDefaults.set(true, forKey: "known-hosts-migrated-to-real-v1")
        }

        reload()
    }

    func reload() {
        do {
            connections = try repository.loadConnections()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load saved tethers."
        }
    }

    func save(_ draft: ConnectionDraft) {
        do {
            // Load the pre-edit connection (if any) BEFORE saving, so we can tell whether the
            // endpoint (host or port) changed and the old known-host pin is now stale.
            let previous = try repository.loadConnections().first { $0.id == draft.id }
            let connection = draft.connection

            try repository.saveConnection(connection, password: draft.passwordForSaving)

            if let previous, previous.host != connection.host || previous.port != connection.port {
                try knownHostStore.removeHost(host: previous.host, port: previous.port)
            }

            reload()
        } catch {
            errorMessage = "Could not save this tether."
        }
    }

    func delete(_ connection: Connection) {
        do {
            try repository.deleteConnection(id: connection.id)
            try knownHostStore.removeHost(host: connection.host, port: connection.port)
            reload()
        } catch {
            errorMessage = "Could not delete this tether."
        }
    }

    func toggleFavorite(_ connection: Connection) {
        do {
            try repository.toggleFavorite(id: connection.id)
            reload()
        } catch {
            errorMessage = "Could not update favorite state."
        }
    }

    func hasPassword(for connection: Connection) -> Bool {
        repository.hasPassword(for: connection.id)
    }

    func terminalRequest(for connection: Connection) async -> TerminalConnectionRequest? {
        connectGeneration += 1
        let generation = connectGeneration
        connectPhase = .verifyingHostKey

        do {
            guard let password = try repository.password(for: connection.id), !password.isEmpty else {
                guard generation == connectGeneration else { return nil }
                let message = SSHClientError.missingPassword.localizedDescription
                errorMessage = message
                connectPhase = .failed(message)
                return nil
            }

            let decision = try await hostKeyTrustEvaluator.evaluate(connection: connection)

            // If the attempt was cancelled or superseded while the capture was in flight, drop the
            // result silently rather than clobbering the (now cleared / restarted) UI state.
            guard generation == connectGeneration else { return nil }

            switch decision {
            case .trusted:
                errorMessage = nil
                connectPhase = nil                    // hand off to the session-picker cover
                return TerminalConnectionRequest(connection: connection, password: password)
            case .unknown(let challenge):
                errorMessage = nil
                connectPhase = nil                    // clear the overlay; the trust prompt takes over
                hostKeyChallenge = challenge
                return nil
            case .changed(let expected, let actual):
                let message = "Host key changed. Expected \(expected), got \(actual). Connection blocked."
                errorMessage = message
                connectPhase = .failed(message)
                return nil
            }
        } catch {
            guard generation == connectGeneration else { return nil }
            let message = "Could not verify this tether's host key."
            errorMessage = message
            connectPhase = .failed(message)
            return nil
        }
    }

    /// Dismisses the progress overlay and invalidates any in-flight connect attempt so its late
    /// result can no longer reopen the overlay or navigate. Also clears any connect-failure banner
    /// so backing out of a failed attempt doesn't leave a stale warning on the host list.
    func cancelConnect() {
        connectGeneration += 1
        connectPhase = nil
        errorMessage = nil
    }

    func trustHostKey(_ challenge: HostKeyChallenge) -> TerminalConnectionRequest? {
        do {
            hostKeyChallenge = nil
            errorMessage = nil
            try hostKeyTrustEvaluator.trust(challenge)

            // The password is deliberately never carried through the host-key challenge.
            // Reload it fresh from the Keychain now that the host is trusted.
            guard let password = try repository.password(for: challenge.connection.id), !password.isEmpty else {
                errorMessage = SSHClientError.missingPassword.localizedDescription
                return nil
            }

            return TerminalConnectionRequest(connection: challenge.connection, password: password)
        } catch {
            errorMessage = "Could not save this host key."
            return nil
        }
    }

    func cancelHostKeyTrust() {
        hostKeyChallenge = nil
    }

    /// Builds a coordinator for a fresh connect journey, wiring it to this view model's
    /// (already-audited) host-key evaluation and trust logic.
    func makeConnectionFlow(for connection: Connection) -> ConnectionFlowCoordinator {
        ConnectionFlowCoordinator(connection: connection, host: self)
    }
}

extension HostListViewModel: ConnectionFlowHost {}

struct ConnectionDraft: Equatable {
    var id: UUID
    var alias: String
    var host: String
    var port: String
    var username: String
    var password: String
    var isFavorite: Bool
    var createdAt: Date

    init(connection: Connection? = nil) {
        let connection = connection ?? Connection(alias: "", host: "", username: "")
        id = connection.id
        alias = connection.alias
        host = connection.host
        port = String(connection.port)
        username = connection.username
        password = ""
        isFavorite = connection.isFavorite
        createdAt = connection.createdAt
    }

    var isValid: Bool {
        ConnectionInputValidation.isValidAlias(trimmedAlias) &&
            ConnectionInputValidation.isValidHost(trimmedHost) &&
            ConnectionInputValidation.isValidUsername(trimmedUsername) &&
            parsedPort != nil
    }

    var connection: Connection {
        Connection(
            id: id,
            alias: trimmedAlias,
            host: ConnectionInputValidation.normalizeHost(trimmedHost),
            port: parsedPort ?? 22,
            username: trimmedUsername,
            isFavorite: isFavorite,
            createdAt: createdAt
        )
    }

    private var trimmedAlias: String {
        alias.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var passwordForSaving: String? {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : password
    }

    private var parsedPort: Int? {
        guard let value = Int(port), ConnectionInputValidation.isValidPort(value) else {
            return nil
        }

        return value
    }
}
