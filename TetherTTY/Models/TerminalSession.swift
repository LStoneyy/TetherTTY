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

    var startupCommand: String? {
        switch provider {
        case .tmux(let name, _, _, _):
            return "tmux attach-session -t \(name)"
        case .herdr(_, _, _, let attachCommand, _):
            return attachCommand
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
