import Foundation

/// A typed representation of the command that should be sent to the remote shell
/// immediately after a terminal session opens.
///
/// This exists so that raw, lower-trust strings (a tmux session name, or a
/// pre-built herdr attach command discovered via `herdr session list --json`)
/// are never interpolated directly into a shell command string at multiple call
/// sites. Instead, they are carried as data inside this enum, validated, and
/// rendered to an actual command string EXACTLY ONCE, at the SSH boundary
/// (`PlainTerminalViewModel`, right before the command is sent).
enum TerminalStartupAction: Equatable {
    /// Attach to a tmux session by name. `sessionName` is the raw, untrusted
    /// session name (e.g. as reported by `tmux list-sessions`).
    case tmuxAttach(sessionName: String)

    /// Run the attach command discovered via `herdr session list --json`.
    /// `command` is a full, pre-built shell command string (not a single
    /// argument), so it must NOT be whole-string single-quoted — doing so would
    /// break it.
    case herdrAttach(command: String)

    /// Maximum RAW (pre-quoting) length allowed for a tmux session name.
    /// tmux session names are short, human-chosen identifiers; 256 bytes is far
    /// more than any legitimate name needs and simply bounds worst-case input.
    static let maxTmuxSessionNameLength = 256

    /// Maximum RAW length allowed for a herdr attach command. This is a full
    /// command line (not a single argument), so the bound is larger than the
    /// tmux session name limit, but still well beyond what any legitimate
    /// discovery-generated attach command should need.
    static let maxHerdrCommandLength = 1024

    /// Renders this action to the exact shell command string that will be sent
    /// to the remote shell (without a trailing newline), or `nil` if the
    /// underlying raw data fails validation. When `nil` is returned, callers
    /// MUST send nothing — never a partial/broken command.
    func renderStartupCommand() -> String? {
        switch self {
        case .tmuxAttach(let sessionName):
            guard Self.isSafe(sessionName, maxLength: Self.maxTmuxSessionNameLength) else { return nil }
            // POSIX single-argument quoting: wrap in single quotes, and replace
            // every embedded `'` with `'\''` (close quote, escaped literal quote,
            // reopen quote). This makes the session name safe to place inside
            // the command regardless of spaces, `;`, `$`, backticks, etc. There
            // is no length limit AFTER quoting.
            return "tmux attach-session -t \(Self.posixSingleQuote(sessionName))"

        case .herdrAttach(let command):
            // The herdr attach command is a full pre-built command string coming
            // from `herdr session list --json` discovery output, not a single
            // argument — so we deliberately do NOT whole-string single-quote it
            // (that would break the command, e.g. turning `herdr session attach
            // prod` into a no-op string literal). Even a fully compromised
            // remote server already controls everything written to our
            // terminal, so the relevant trust boundary here is not the server
            // itself but lower-trust/malformed discovery output. Rejecting
            // embedded CR/LF/NUL is what actually matters: it prevents
            // command-injection-via-newline, i.e. discovery output smuggling in
            // and executing extra shell commands after the intended one.
            guard Self.isSafe(command, maxLength: Self.maxHerdrCommandLength) else { return nil }
            return command
        }
    }

    /// Rejects raw input containing NUL/CR/LF (which could break out of the
    /// single line sent to the remote shell) or exceeding `maxLength` raw bytes.
    private static func isSafe(_ value: String, maxLength: Int) -> Bool {
        guard !value.isEmpty else { return false }
        guard !containsControlChars(value) else { return false }
        guard value.utf8.count <= maxLength else { return false }
        return true
    }

    private static func containsControlChars(_ value: String) -> Bool {
        value.contains("\0") || value.contains("\r") || value.contains("\n")
    }

    private static func posixSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
