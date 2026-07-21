import XCTest
@testable import TetherTTY

final class HostKeyTrustEvaluatorTests: XCTestCase {
    func testUnknownHostReturnsTrustChallenge() async throws {
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: InMemoryKnownHostStore(),
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )

        let decision = try await evaluator.evaluate(connection: connection(), password: "secret")

        guard case .unknown(let challenge) = decision else {
            return XCTFail("Expected unknown host challenge")
        }

        XCTAssertEqual(challenge.connection.host, "192.0.2.42")
        XCTAssertEqual(challenge.password, "secret")
        XCTAssertEqual(challenge.fingerprint, "SHA256:first")
    }

    func testTrustedHostAllowsConnection() async throws {
        let store = InMemoryKnownHostStore()
        try store.trustHost(host: "192.0.2.42", port: 22, fingerprint: "SHA256:first")
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )

        let decision = try await evaluator.evaluate(connection: connection(), password: "secret")

        XCTAssertEqual(decision, .trusted)
    }

    func testChangedHostKeyBlocksConnection() async throws {
        let store = InMemoryKnownHostStore()
        try store.trustHost(host: "192.0.2.42", port: 22, fingerprint: "SHA256:first")
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:changed")
        )

        let decision = try await evaluator.evaluate(connection: connection(), password: "secret")

        XCTAssertEqual(decision, .changed(expected: "SHA256:first", actual: "SHA256:changed"))
    }

    func testTrustingChallengeStoresKnownHostAndReturnsTerminalRequest() throws {
        let store = InMemoryKnownHostStore()
        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: store,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:first")
        )
        let challenge = HostKeyChallenge(connection: connection(), password: "secret", fingerprint: "SHA256:first")

        let request = try evaluator.trust(challenge)

        XCTAssertEqual(request.connection, challenge.connection)
        XCTAssertEqual(request.password, "secret")
        XCTAssertEqual(try store.knownHost(host: "192.0.2.42", port: 22)?.fingerprint, "SHA256:first")
    }

    private func connection() -> Connection {
        Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas")
    }
}

struct FixedFingerprintResolver: HostKeyFingerprintResolver {
    let fingerprint: String

    func fingerprint(for connection: Connection, password: String) async throws -> String {
        fingerprint
    }
}
