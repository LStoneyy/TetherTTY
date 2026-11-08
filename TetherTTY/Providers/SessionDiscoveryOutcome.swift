import Foundation

/// The CLI tool a session-discovery provider shells out to, used only to tailor diagnostic
/// messages and tool-specific classification rules.
enum SessionDiscoveryTool: Equatable {
    case tmux
    case herdr

    var displayName: String {
        switch self {
        case .tmux: "tmux"
        case .herdr: "herdr"
        }
    }
}

/// Outcome of a single session-discovery attempt (tmux or herdr), classified so the UI can tell
/// apart "the tool simply isn't installed" (neutral) from "the tool is installed but something
/// went wrong" (a real diagnostic worth surfacing as a warning).
enum SessionDiscoveryOutcome: Equatable {
    /// Discovery ran cleanly; any resulting sessions (including zero) speak for themselves.
    case ok
    /// The remote shell could not find the tool at all (`exit 127`, "command not found").
    case notInstalled
    /// Discovery produced a worth-showing diagnostic message (trimmed stderr, or a synthesized
    /// "<tool> exited N" fallback when stderr was empty).
    case diagnostic(String)
}

/// Shared, pure classification logic used by both `RealTmuxSessionProvider` and
/// `RealHerdrSessionProvider` to turn a raw shell exec result into a `SessionDiscoveryOutcome`.
enum SessionDiscoveryClassifier {
    /// - Parameters:
    ///   - tool: which CLI was invoked (used for tool-specific rules and message text).
    ///   - exitStatus: the shell command's exit status.
    ///   - stderr: raw stderr from the command (trimmed internally).
    ///   - sessionCount: number of sessions successfully parsed from stdout.
    static func classify(
        tool: SessionDiscoveryTool,
        exitStatus: Int,
        stderr: String,
        sessionCount: Int
    ) -> SessionDiscoveryOutcome {
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        // "command not found" from the remote shell: the tool simply isn't installed.
        if exitStatus == 127 {
            return .notInstalled
        }

        if exitStatus != 0 {
            if tool == .tmux {
                let lowered = trimmedStderr.lowercased()
                if lowered.contains("no server running") || lowered.contains("error connecting to") {
                    // tmux reports this as a failure, but it just means zero sessions exist yet.
                    return .ok
                }
            }
            return .diagnostic(
                trimmedStderr.isEmpty ? "\(tool.displayName) exited \(exitStatus)" : trimmedStderr
            )
        }

        if sessionCount == 0 && !trimmedStderr.isEmpty {
            return .diagnostic(trimmedStderr)
        }

        return .ok
    }
}
