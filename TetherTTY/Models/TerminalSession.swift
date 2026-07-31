import Foundation

enum SessionProviderType: Equatable {
    case plainShell
    case tmux(name: String, windowCount: Int, attachedCount: Int, created: Date?)
    case herdr(kind: String, name: String, status: String, attachCommand: String, metadata: String?)
}

struct TerminalSession: Identifiable, Equatable {
    let id: String
    let provider: SessionProviderType
    let displayName: String
    let detail: String

    /// The typed startup action for this session, if any. Rendering this to an
    /// actual shell command string happens exactly once, at the SSH boundary
    /// (see `TerminalStartupAction.renderStartupCommand()`).
    var startupAction: TerminalStartupAction? {
        switch provider {
        case .tmux(let name, _, _, _):
            return .tmuxAttach(sessionName: name)
        case .herdr(_, _, _, let attachCommand, _):
            return .herdrAttach(command: attachCommand)
        case .plainShell:
            return nil
        }
    }
}

extension TerminalSession {
    static let plainShellSession = TerminalSession(
        id: "plain-shell",
        provider: .plainShell,
        displayName: "Plain Shell",
        detail: "Open a standard shell session"
    )
}
