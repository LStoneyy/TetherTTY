import Foundation

enum TerminalConnectionState: Equatable {
    case idle
    case connecting
    case authenticating
    case terminalOpen
    case reconnecting
    case disconnected
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .authenticating: "Authenticating"
        case .terminalOpen: "Terminal Open"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }
}

struct TerminalConnectionRequest: Identifiable, Equatable {
    let id = UUID()
    let connection: Connection
    let password: String
    let startupAction: TerminalStartupAction?

    init(connection: Connection, password: String, startupAction: TerminalStartupAction? = nil) {
        self.connection = connection
        self.password = password
        self.startupAction = startupAction
    }
}
