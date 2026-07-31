import XCTest
@testable import TetherTTY

/// Regression tests for the real (NIO-backed) host-key capture path.
///
/// These exercise `RealHostKeyFingerprintResolver` directly — the production code that the
/// simulated resolver used elsewhere never covers. They guard against the on-device
/// "Fatal error: leaking promise" crash: when the capture connection fails before the host key
/// is validated, the resolver must throw a clean error instead of leaking an unfulfilled
/// `EventLoopPromise` (which aborts the app in debug builds).
final class RealHostKeyResolverTests: XCTestCase {

    func testFingerprintAgainstClosedPortThrowsCleanly() async {
        let resolver = RealHostKeyFingerprintResolver()
        // Port 1 on loopback: nothing listens there, so the TCP connect is refused. On the
        // pre-fix code this crashed with a leaking promise; it must now throw cleanly.
        let connection = Connection(alias: "unreachable", host: "127.0.0.1", port: 1, username: "nobody")

        do {
            _ = try await resolver.fingerprint(for: connection)
            XCTFail("Expected connecting to a closed port to throw, not succeed")
        } catch {
            // Success: a thrown error (no crash, no leaked promise).
        }
    }
}
