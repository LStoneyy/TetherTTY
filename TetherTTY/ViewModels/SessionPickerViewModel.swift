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
        tmuxProvider: TmuxSessionProvider = RealTmuxSessionProvider(),
        herdrProvider: HerdrSessionProvider = RealHerdrSessionProvider()
    ) {
        self.request = request
        self.tmuxProvider = tmuxProvider
        self.herdrProvider = herdrProvider
    }

    func fetchSessions() async {
        isLoading = true
        errorMessage = nil
        herdrErrorMessage = nil

        let tmuxTask = Task { try await tmuxProvider.fetchSessions(for: request) }
        let herdrTask = Task { try await herdrProvider.fetchSessions(for: request) }

        var tmuxSessions: [TerminalSession] = []
        var herdrSessions: [TerminalSession] = []

        switch await tmuxTask.result {
        case .success(let sessions):
            tmuxSessions = sessions
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        switch await herdrTask.result {
        case .success(let sessions):
            herdrSessions = sessions
        case .failure(let error):
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
