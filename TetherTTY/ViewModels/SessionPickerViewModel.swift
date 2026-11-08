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
    @Published private(set) var tmuxNotInstalled = false
    @Published private(set) var herdrNotInstalled = false

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
        tmuxNotInstalled = false
        herdrNotInstalled = false

        let tmuxTask = Task { try await tmuxProvider.fetchSessions(for: request) }
        let herdrTask = Task { try await herdrProvider.fetchSessions(for: request) }

        switch await tmuxTask.result {
        case .success(let result):
            tmuxSessions = result.sessions
            switch result.outcome {
            case .ok:
                break
            case .notInstalled:
                tmuxNotInstalled = true
            case .diagnostic(let message):
                tmuxDiagnostic = message
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        switch await herdrTask.result {
        case .success(let result):
            herdrSessions = result.sessions
            switch result.outcome {
            case .ok:
                break
            case .notInstalled:
                herdrNotInstalled = true
            case .diagnostic(let message):
                herdrDiagnostic = message
            }
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
