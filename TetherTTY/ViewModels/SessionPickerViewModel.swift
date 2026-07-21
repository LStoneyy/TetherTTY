import Foundation

@MainActor
final class SessionPickerViewModel: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private let request: TerminalConnectionRequest
    private let provider: TmuxSessionProvider

    init(
        request: TerminalConnectionRequest,
        provider: TmuxSessionProvider = SimulatedTmuxSessionProvider()
    ) {
        self.request = request
        self.provider = provider
    }

    func fetchSessions() async {
        isLoading = true
        errorMessage = nil

        do {
            let discovered = try await provider.fetchSessions(for: request)
            sessions = discovered
        } catch {
            errorMessage = error.localizedDescription
        }

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
