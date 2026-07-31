import Foundation

@MainActor
final class SessionPickerViewModel: ObservableObject {
    @Published private(set) var tmuxSessions: [TerminalSession] = []
    @Published private(set) var herdrSessions: [TerminalSession] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    @Published var herdrErrorMessage: String?
    @Published var tmuxDiagnostic: String?
    @Published var herdrDiagnostic: String?

    var sessions: [TerminalSession] {
        tmuxSessions + herdrSessions + [.plainShellSession]
    }

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
        tmuxDiagnostic = nil
        herdrDiagnostic = nil

        let tmuxTask = Task { try await tmuxProvider.fetchSessions(for: request) }
        let herdrTask = Task { try await herdrProvider.fetchSessions(for: request) }

        switch await tmuxTask.result {
        case .success(let result):
            tmuxSessions = result.0
            tmuxDiagnostic = result.1
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        switch await herdrTask.result {
        case .success(let result):
            herdrSessions = result.0
            herdrDiagnostic = result.1
        case .failure(let error):
            herdrErrorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func makeTerminalRequest(for session: TerminalSession) -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: request.connection,
            password: request.password,
            startupAction: session.startupAction
        )
    }

    var plainShellRequest: TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: request.connection,
            password: request.password,
            startupAction: nil
        )
    }
}
