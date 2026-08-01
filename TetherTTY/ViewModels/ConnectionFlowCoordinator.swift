import Foundation

/// The connect-flow engine the coordinator drives. `HostListViewModel` supplies the real
/// implementation; the protocol keeps the coordinator unit-testable with a fake host and reuses the
/// already-audited host-key logic instead of duplicating it.
@MainActor
protocol ConnectionFlowHost: AnyObject {
    var hostKeyChallenge: HostKeyChallenge? { get }
    var connectPhase: ConnectionPhase? { get }
    func terminalRequest(for connection: Connection) async -> TerminalConnectionRequest?
    func trustHostKey(_ challenge: HostKeyChallenge) -> TerminalConnectionRequest?
    func cancelConnect()
    func cancelHostKeyTrust()
}

/// Owns a single, continuous connect journey — host-key verification, inline trust, session
/// discovery, terminal — as one `phase` the flow view renders. Presented immediately when the user
/// taps Connect, so every previously silent or pop-up station becomes an announced step of one calm
/// flow.
@MainActor
final class ConnectionFlowCoordinator: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    let connection: Connection

    @Published private(set) var phase: ConnectionPhase = .verifyingHostKey

    /// The request in play: the base (connection + password) while picking a session, then the
    /// session-specific request once one is chosen or a reconnect is requested.
    private(set) var activeRequest: TerminalConnectionRequest?

    private let host: ConnectionFlowHost
    private var task: Task<Void, Never>?

    init(connection: Connection, host: ConnectionFlowHost) {
        self.connection = connection
        self.host = host
    }

    var address: String { connection.displayAddress }

    /// Kicks off (or restarts) host-key verification and routes to the next station.
    func start() {
        task?.cancel()
        phase = .verifyingHostKey
        task = Task { [weak self] in
            guard let self else { return }
            let request = await host.terminalRequest(for: connection)
            if Task.isCancelled { return }

            if let request {
                activeRequest = request
                phase = .pickingSession
            } else if let challenge = host.hostKeyChallenge {
                phase = .trustPrompt(challenge)
            } else if case .failed(let message)? = host.connectPhase {
                phase = .failed(message)
            } else {
                // The attempt was cancelled/superseded (host cleared its phase): leave the flow as
                // whatever it is now rather than forcing a spurious failure.
                return
            }
        }
    }

    /// User accepted the fingerprint on the inline trust card.
    func trustCurrentHost() {
        guard case .trustPrompt(let challenge) = phase else { return }
        if let request = host.trustHostKey(challenge) {
            activeRequest = request
            phase = .pickingSession
        } else {
            phase = .failed("Could not save this host key.")
        }
    }

    /// A session (or plain shell) was chosen in the picker.
    func selectSession(_ request: TerminalConnectionRequest) {
        activeRequest = request
        phase = .terminal
    }

    /// The terminal dropped and the user asked to reattach: return to discovery with a fresh,
    /// startup-command-free request so the reattach is announced, not silent.
    func requestReconnect(_ request: TerminalConnectionRequest) {
        activeRequest = request
        phase = .pickingSession
    }

    /// Retry after a failure — re-runs verification from the top.
    func retry() {
        start()
    }

    /// The whole flow was dismissed (Cancel / Back / Close): stop in-flight work and clear any
    /// pending host state so the next attempt starts clean.
    func cancel() {
        task?.cancel()
        host.cancelConnect()
        host.cancelHostKeyTrust()
    }

    /// Test hook: await the in-flight verification/retry task so assertions run after the phase has
    /// settled.
    func awaitSettled() async {
        await task?.value
    }
}
