import Foundation

protocol TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> [TerminalSession]
}

struct SimulatedTmuxSessionProvider: TmuxSessionProvider {
    func fetchSessions(for request: TerminalConnectionRequest) async throws -> [TerminalSession] {
        try await Task.sleep(nanoseconds: 500_000_000)
        let now = Date()
        return [
            TerminalSession(
                id: "shell",
                provider: .tmux(
                    name: "shell",
                    windowCount: 2,
                    attachedCount: 1,
                    created: now.addingTimeInterval(-86400)
                ),
                displayName: "shell",
                detail: "2 windows, 1 attached"
            ),
            TerminalSession(
                id: "editor",
                provider: .tmux(
                    name: "editor",
                    windowCount: 3,
                    attachedCount: 0,
                    created: now.addingTimeInterval(-3600)
                ),
                displayName: "editor",
                detail: "3 windows, 0 attached"
            ),
        ]
    }
}
