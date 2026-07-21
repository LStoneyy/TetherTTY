import CryptoKit
import Foundation

protocol HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection) throws -> String
}

struct SimulatedHostKeyFingerprintResolver: HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection) throws -> String {
        let input = "\(connection.host.lowercased()):\(connection.port)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return "SHA256:" + Data(digest).base64EncodedString()
    }
}

struct HostKeyTrustEvaluator {
    let knownHostStore: KnownHostStore
    let fingerprintResolver: HostKeyFingerprintResolver

    init(
        knownHostStore: KnownHostStore = LocalKnownHostStore(),
        fingerprintResolver: HostKeyFingerprintResolver = SimulatedHostKeyFingerprintResolver()
    ) {
        self.knownHostStore = knownHostStore
        self.fingerprintResolver = fingerprintResolver
    }

    func evaluate(connection: Connection, password: String) throws -> HostKeyTrustDecision {
        let actual = try fingerprintResolver.fingerprint(for: connection)

        guard let knownHost = try knownHostStore.knownHost(host: connection.host, port: connection.port) else {
            return .unknown(HostKeyChallenge(connection: connection, password: password, fingerprint: actual))
        }

        guard knownHost.fingerprint == actual else {
            return .changed(expected: knownHost.fingerprint, actual: actual)
        }

        return .trusted
    }

    func trust(_ challenge: HostKeyChallenge) throws -> TerminalConnectionRequest {
        try knownHostStore.trustHost(
            host: challenge.connection.host,
            port: challenge.connection.port,
            fingerprint: challenge.fingerprint
        )

        return TerminalConnectionRequest(connection: challenge.connection, password: challenge.password)
    }
}
