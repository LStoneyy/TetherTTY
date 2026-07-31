import XCTest
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
@testable import TetherTTY

/// Fixture tests for Phase 1 of the SSH trust-boundary remediation (SEC-01, SEC-02, SEC-09):
/// - Host-key verification must fail-closed for unknown hosts and known-hosts store errors.
/// - A matching known host still succeeds, and a mismatching one still fails.
/// - The fingerprint resolver pipeline no longer threads a password through it.
final class HostKeySecurityFixturesTests: XCTestCase {
    private var group: MultiThreadedEventLoopGroup!

    override func setUp() {
        super.setUp()
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDown() {
        try? group.syncShutdownGracefully()
        group = nil
        super.tearDown()
    }

    // Real (but throwaway, never used for anything but this test file) ed25519 OpenSSH public
    // keys. No private key material appears anywhere in this repository.
    private static let keyA = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmavJIwzlCxoDOCEt6UhBch4iK5QIPpDZrAVQ2iLOXS"
    private static let keyB = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP4Kss+ueGOeDasa1k67v5D1woRSgZuSZBmmp+xcI2/3"

    private func hostKey(_ openSSH: String) throws -> NIOSSHPublicKey {
        try NIOSSHPublicKey(openSSHPublicKey: openSSH)
    }

    private func validate(_ delegate: VerifyingHostKeyDelegate, hostKey: NIOSSHPublicKey) async throws {
        let promise = group.next().makePromise(of: Void.self)
        delegate.validateHostKey(hostKey: hostKey, validationCompletePromise: promise)
        try await promise.futureResult.get()
    }

    func testUnknownHostFailsClosed() async throws {
        let delegate = VerifyingHostKeyDelegate(
            knownHostStore: InMemoryKnownHostStore(),
            host: "unknown.example.com",
            port: 22
        )

        do {
            try await validate(delegate, hostKey: hostKey(Self.keyA))
            XCTFail("Expected an unknown host to fail validation (fail-closed)")
        } catch let error as SSHClientError {
            XCTAssertEqual(error, .hostKeyUnknown)
        }
    }

    func testStoreErrorFailsClosed() async throws {
        let delegate = VerifyingHostKeyDelegate(
            knownHostStore: ThrowingKnownHostStore(),
            host: "broken.example.com",
            port: 22
        )

        do {
            try await validate(delegate, hostKey: hostKey(Self.keyA))
            XCTFail("Expected a known-hosts store read error to fail validation (fail-closed)")
        } catch let error as SSHClientError {
            XCTAssertEqual(error, .hostKeyStoreError)
        }
    }

    func testKnownHostMatchSucceeds() async throws {
        let store = InMemoryKnownHostStore()
        let key = try hostKey(Self.keyA)
        let fingerprint = SHA256HostKeyFingerprintFormatter.format(key)
        try store.trustHost(host: "known.example.com", port: 22, fingerprint: fingerprint)

        let delegate = VerifyingHostKeyDelegate(knownHostStore: store, host: "known.example.com", port: 22)

        // Should not throw.
        try await validate(delegate, hostKey: key)
    }

    func testKnownHostMismatchFails() async throws {
        let store = InMemoryKnownHostStore()
        try store.trustHost(host: "changed.example.com", port: 22, fingerprint: "SHA256:not-the-real-one")

        let delegate = VerifyingHostKeyDelegate(knownHostStore: store, host: "changed.example.com", port: 22)

        do {
            try await validate(delegate, hostKey: hostKey(Self.keyB))
            XCTFail("Expected a mismatching host key to fail validation")
        } catch let error as SSHClientError {
            guard case .hostKeyChanged = error else {
                return XCTFail("Expected .hostKeyChanged, got \(error)")
            }
        }
    }

    /// Compile-time / interface proof for SEC-02: the fingerprint resolver pipeline no longer
    /// threads a password through it. If this file compiles and this call type-checks against
    /// `HostKeyFingerprintResolver.fingerprint(for:)` with no `password` argument, the pipeline
    /// no longer carries a password down to host-key capture.
    func testFingerprintResolverHasNoPasswordParameter() async throws {
        struct RecordingResolver: HostKeyFingerprintResolver {
            func fingerprint(for connection: Connection) async throws -> String {
                "SHA256:no-password-needed"
            }
        }

        let connection = Connection(alias: "NoPassword", host: "nopass.example.com", username: "lukas")
        let resolver: HostKeyFingerprintResolver = RecordingResolver()

        let fingerprint = try await resolver.fingerprint(for: connection)

        XCTAssertEqual(fingerprint, "SHA256:no-password-needed")
    }
}

/// A `KnownHostStore` that always throws on read, to exercise the fail-closed path when the
/// local known-hosts store cannot be read.
private final class ThrowingKnownHostStore: KnownHostStore {
    struct StoreReadError: Error {}

    func knownHost(host: String, port: Int) throws -> KnownHost? {
        throw StoreReadError()
    }

    func trustHost(host: String, port: Int, fingerprint: String) throws {}
    func removeHost(host: String, port: Int) throws {}
    func clearAll() throws {}
}
