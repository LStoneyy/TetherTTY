import Foundation

/// User-facing progress through the connect flow, deliberately separate from the technical
/// `TerminalConnectionState` (which only tracks the live SSH session). It supplies the copy and
/// symbol for `ConnectionProgressOverlay` and, in the unified flow, drives
/// `ConnectionFlowCoordinator`.
///
/// The goal is that nothing surprises the user: the host-key check and session discovery become
/// visible, announced stations instead of silent gaps followed by pop-ups.
enum ConnectionPhase: Equatable {
    case verifyingHostKey
    case trustPrompt(HostKeyChallenge)
    case loadingSessions
    case pickingSession
    case openingTerminal            // covers TerminalConnectionState.connecting + .authenticating
    case terminal
    case failed(String)

    var title: String {
        switch self {
        case .verifyingHostKey: "Verifying host key…"
        case .trustPrompt: "New host"
        case .loadingSessions: "Discovering sessions…"
        case .pickingSession: "Choose a session"
        case .openingTerminal: "Opening terminal…"
        case .terminal: "Terminal"
        case .failed: "Couldn't connect"
        }
    }

    /// SF Symbol representing the phase.
    var symbol: String {
        switch self {
        case .verifyingHostKey: "lock.shield"
        case .trustPrompt: "questionmark.shield"
        case .loadingSessions: "rectangle.stack"
        case .pickingSession: "list.bullet.rectangle"
        case .openingTerminal: "terminal"
        case .terminal: "terminal.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// Static supporting copy that does not depend on the connection address. Address-based
    /// subtitles (`user@host:port`) are supplied by the view layer through `subtitle(address:)`.
    var detail: String? {
        switch self {
        case .trustPrompt: "Review the fingerprint before trusting"
        case .loadingSessions: "Looking for tmux and herdr"
        case .failed(let message): message
        default: nil
        }
    }

    /// True while the phase represents active, indeterminate work — the overlay shows a spinner.
    var isWorking: Bool {
        switch self {
        case .verifyingHostKey, .loadingSessions, .openingTerminal: true
        default: false
        }
    }

    /// True for a terminal error state — the overlay swaps its spinner for a warning and offers
    /// retry/back affordances.
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// The subtitle shown by the overlay: the connection address for the network phases, otherwise
    /// the static `detail` copy.
    func subtitle(address: String?) -> String? {
        switch self {
        case .verifyingHostKey, .openingTerminal: address
        default: detail
        }
    }
}
