import Foundation

enum TerminalConnectionState: Equatable {
    case idle
    case connecting
    case authenticating
    case terminalOpen
    case disconnected
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .authenticating: "Authenticating"
        case .terminalOpen: "Terminal Open"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }
}

struct TerminalConnectionRequest: Identifiable, Equatable {
    let id = UUID()
    let connection: Connection
    let password: String
}
