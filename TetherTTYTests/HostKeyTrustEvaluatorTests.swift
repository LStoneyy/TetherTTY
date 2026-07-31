import XCTest
@testable import TetherTTY

final class HostKeyTrustEvaluatorTests: XCTestCase {
    func testUnknownHostReturnsTrustChallenge() async throws {
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: InMemoryKnownHostStore(),
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )

        let decision = try await evaluator.evaluate(connection: connection())

        guard case .unknown(let challenge) = decision else {
            return XCTFail("Expected unknown host challenge")
        }

        XCTAssertEqual(challenge.connection.host, "192.0.2.42")
        XCTAssertEqual(challenge.fingerprint, "SHA256:first")
    }

    func testTrustedHostAllowsConnection() async throws {
        let store = InMemoryKnownHostStore()
        try store.trustHost(host: "192.0.2.42", port: 22, fingerprint: "SHA256:first")
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )

        let decision = try await evaluator.evaluate(connection: connection())

        XCTAssertEqual(decision, .trusted)
    }

    func testChangedHostKeyBlocksConnection() async throws {
        let store = InMemoryKnownHostStore()
        try store.trustHost(host: "192.0.2.42", port: 22, fingerprint: "SHA256:first")
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:changed")
        )

        let decision = try await evaluator.evaluate(connection: connection())

        XCTAssertEqual(decision, .changed(expected: "SHA256:first", actual: "SHA256:changed"))
    }

    func testTrustingChallengeStoresKnownHost() throws {
        let store = InMemoryKnownHostStore()
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )
        let challenge = HostKeyChallenge(connection: connection(), fingerprint: "SHA256:first")

        try evaluator.trust(challenge)

        XCTAssertEqual(try store.knownHost(host: "192.0.2.42", port: 22)?.fingerprint, "SHA256:first")
    }

    private func connection() -> Connection {
        Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas")
    }
}

struct FixedFingerprintResolver: HostKeyFingerprintResolver {
    let fingerprint: String

    func fingerprint(for connection: Connection) async throws -> String {
        fingerprint
    }
}
