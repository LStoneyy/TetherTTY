import Foundation

@MainActor
final class SessionPickerViewModel: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    @Published var herdrErrorMessage: String?

    private let request: TerminalConnectionRequest
    private let tmuxProvider: TmuxSessionProvider
    private let herdrProvider: HerdrSessionProvider

    init(
        request: TerminalConnectionRequest,
        tmuxProvider: TmuxSessionProvider = SimulatedTmuxSessionProvider(),
        herdrProvider: HerdrSessionProvider = SimulatedHerdrSessionProvider()
    ) {
        self.request = request
        self.tmuxProvider = tmuxProvider
        self.herdrProvider = herdrProvider
    }

    func fetchSessions() async {
        isLoading = true
        errorMessage = nil
        herdrErrorMessage = nil

        var tmuxSessions: [TerminalSession] = []
        var herdrSessions: [TerminalSession] = []

        do {
            tmuxSessions = try await tmuxProvider.fetchSessions(for: request)
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            herdrSessions = try await herdrProvider.fetchSessions(for: request)
        } catch {
            herdrErrorMessage = error.localizedDescription
        }

        var combined = tmuxSessions + herdrSessions
        combined.append(.plainShellSession)
        sessions = combined
        isLoading = false
    }

    func makeTerminalRequest(for session: TerminalSession) -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: request.connection,
            password: request.password,
            startupCommand: session.startupCommand
        )
    }

    var plainShellRequest: TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: request.connection,
            password: request.password,
            startupCommand: nil
        )
    }
}
