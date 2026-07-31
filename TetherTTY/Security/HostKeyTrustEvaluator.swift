import CryptoKit
import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSH

protocol HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection) async throws -> String
}

struct SimulatedHostKeyFingerprintResolver: HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection) async throws -> String {
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
        fingerprintResolver: HostKeyFingerprintResolver = RealHostKeyFingerprintResolver()
    ) {
        self.knownHostStore = knownHostStore
        self.fingerprintResolver = fingerprintResolver
    }

    /// Captures the host key's fingerprint (without authenticating as any user) and compares it
    /// against the locally stored known-hosts entry for this host/port.
    func evaluate(connection: Connection) async throws -> HostKeyTrustDecision {
        let actual = try await fingerprintResolver.fingerprint(for: connection)

        guard let knownHost = try knownHostStore.knownHost(host: connection.host, port: connection.port) else {
            return .unknown(HostKeyChallenge(connection: connection, fingerprint: actual))
        }

        guard knownHost.fingerprint == actual else {
            return .changed(expected: knownHost.fingerprint, actual: actual)
        }

        return .trusted
    }

    /// Persists the user's TOFU decision. The password used for the actual connect is intentionally
    /// NOT part of this pipeline; the caller is responsible for reloading it (e.g. from Keychain)
    /// before performing the real connect.
    func trust(_ challenge: HostKeyChallenge) throws {
        try knownHostStore.trustHost(
            host: challenge.connection.host,
            port: challenge.connection.port,
            fingerprint: challenge.fingerprint
        )
    }
}

// MARK: - Real Host Key Fingerprint Resolver

final class RealHostKeyFingerprintResolver: HostKeyFingerprintResolver {
    private let group = NIOSingletons.posixEventLoopGroup

    /// Deadline for the whole capture bootstrap (TCP connect + handshake up to host-key
    /// validation). This is a capture-only connection: it never authenticates as any user,
    /// so it must not be allowed to hang indefinitely.
    private static let captureDeadline: TimeAmount = .seconds(10)

    func fingerprint(for connection: Connection) async throws -> String {
        let delegate = HostKeyCaptureDelegate()

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(Self.captureDeadline)
            .channelInitializer { channel in
                channel.pipeline.addHandlers(
                    NIOSSHHandler(
                        role: .client(.init(
                            // No credentials are offered. NIOSSH validates the server's host key
                            // during key exchange, BEFORE user authentication begins, so this
                            // delegate lets the capturing serverAuthDelegate record the key and
                            // then the handshake is left to fail/close during (declined) user-auth.
                            userAuthDelegate: CaptureOnlyUserAuthDelegate(),
                            serverAuthDelegate: delegate
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    ),
                    NIOCloseOnErrorHandler()
                )
            }

        // TCP connect, bounded by connectTimeout. A failure here simply throws — there is
        // no dangling promise left to leak.
        let channel = try await bootstrap.connect(host: connection.host, port: connection.port).get()

        // Safety net: the capture connection normally closes itself once the host key has been
        // validated and the (declined) user-auth completes. If the peer hangs mid-handshake,
        // force it closed after the deadline so we never wait forever.
        let deadlineTask = channel.eventLoop.scheduleTask(in: Self.captureDeadline) {
            channel.close(promise: nil)
        }

        // Wait for the connection to finish: declined auth after key exchange, a peer close, a
        // handshake error (NIOCloseOnErrorHandler), or our deadline force-close. The channel is
        // guaranteed closed once this resolves, so the capture connection is never left open.
        try? await channel.closeFuture.get()
        deadlineTask.cancel()

        guard let hostKey = delegate.capturedKey else {
            throw SSHClientError.connectionFailed(
                "Could not read the host key from \(connection.host):\(connection.port). "
                + "Check that the host is reachable and running SSH."
            )
        }
        return SHA256HostKeyFingerprintFormatter.format(hostKey)
    }
}

/// A `NIOSSHClientUserAuthenticationDelegate` that offers no authentication credentials at all.
///
/// Used exclusively for host-key capture: NIOSSH validates the server's host key during key
/// exchange, before any user-authentication offer is requested, so by the time this delegate is
/// consulted the fingerprint has already been captured by the `serverAuthDelegate`. Returning
/// `nil` tells NIOSSH "the client has run out of things to try", which cleanly fails the
/// handshake instead of sending any real credential over the wire.
final class CaptureOnlyUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        nextChallengePromise.succeed(nil)
    }
}

public struct SHA256HostKeyFingerprintFormatter {
    public static func format(_ key: NIOSSHPublicKey) -> String {
        let openSSHString = String(openSSHPublicKey: key)
        guard let base64Part = openSSHString.split(separator: " ").dropFirst().first,
              let rawData = Data(base64Encoded: String(base64Part)) else {
            return "SHA256:invalid-key"
        }
        let digest = SHA256.hash(data: rawData)
        return "SHA256:" + Data(digest).base64EncodedString()
    }
}

/// Captures the server's host key during key exchange. Deliberately holds **no** long-lived
/// `EventLoopPromise`: an unfulfilled NIO promise triggers a fatal "leaking promise" error in
/// debug builds whenever the connection fails before host-key validation is reached (unreachable
/// host, wrong port, early handshake failure, …). Instead the key is stored in a lock-protected
/// slot that the caller reads once the capture connection has closed.
final class HostKeyCaptureDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let lock = NSLock()
    private var _capturedKey: NIOSSHPublicKey?

    /// The captured host key, or `nil` if the connection closed before key exchange reached
    /// host-key validation. Safe to read from any thread.
    var capturedKey: NIOSSHPublicKey? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedKey
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        lock.lock()
        _capturedKey = hostKey
        lock.unlock()
        // Accept, so the handshake proceeds to the (declined) user-auth that then closes this
        // capture-only connection.
        validationCompletePromise.succeed(())
    }
}
