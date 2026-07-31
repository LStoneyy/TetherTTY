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

        let channel = try await bootstrap.connect(host: connection.host, port: connection.port).get()

        let outcome: Result<NIOSSHPublicKey, Error>
        do {
            let hostKey = try await Self.awaitHostKey(delegate: delegate, eventLoop: channel.eventLoop)
            outcome = .success(hostKey)
        } catch {
            outcome = .failure(error)
        }

        // Guaranteed cleanup: this connection is capture-only and must never be left open,
        // whether the capture succeeded, failed, or timed out.
        try? await channel.close()

        switch outcome {
        case .success(let hostKey):
            return SHA256HostKeyFingerprintFormatter.format(hostKey)
        case .failure(let error):
            throw error
        }
    }

    private static func awaitHostKey(
        delegate: HostKeyCaptureDelegate,
        eventLoop: EventLoop
    ) async throws -> NIOSSHPublicKey {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let timeoutTask = eventLoop.scheduleTask(in: captureDeadline) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: SSHClientError.connectionFailed("Host key capture timed out"))
            }
            // `delegate.hostKeyFuture` completes on the promise's own home event loop (a
            // separate loop from `NIOSingletons.posixEventLoopGroup`), while the timeout above
            // fires on `eventLoop` (the connection's channel event loop). Hop the future onto
            // `eventLoop` so both completion paths run on the SAME thread; this makes the
            // unsynchronized `didResume` guard race-free instead of a potential double-resume.
            delegate.hostKeyFuture.hop(to: eventLoop).whenComplete { result in
                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                continuation.resume(with: result)
            }
        }
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

final class HostKeyCaptureDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let promise: EventLoopPromise<NIOSSHPublicKey>
    var hostKeyFuture: EventLoopFuture<NIOSSHPublicKey> { promise.futureResult }

    init() {
        promise = NIOSingletons.posixEventLoopGroup.next().makePromise(of: NIOSSHPublicKey.self)
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        promise.succeed(hostKey)
        validationCompletePromise.succeed(())
    }
}
