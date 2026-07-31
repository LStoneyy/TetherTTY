import Foundation

struct KnownHost: Codable, Equatable {
    let host: String
    let port: Int
    let fingerprint: String
    let firstSeenAt: Date

    var key: String { Self.key(host: host, port: port) }

    static func key(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }
}

struct HostKeyChallenge: Identifiable, Equatable {
    let id = UUID()
    let connection: Connection
    let fingerprint: String
}

enum HostKeyTrustDecision: Equatable {
    case trusted
    case unknown(HostKeyChallenge)
    case changed(expected: String, actual: String)
}
