import CryptoKit
import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSH

protocol HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection, password: String) async throws -> String
}

struct SimulatedHostKeyFingerprintResolver: HostKeyFingerprintResolver {
    func fingerprint(for connection: Connection, password: String) async throws -> String {
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

    func evaluate(connection: Connection, password: String) async throws -> HostKeyTrustDecision {
        let actual = try await fingerprintResolver.fingerprint(for: connection, password: password)

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

// MARK: - Real Host Key Fingerprint Resolver

final class RealHostKeyFingerprintResolver: HostKeyFingerprintResolver {
    private let group = NIOSingletons.posixEventLoopGroup

    func fingerprint(for connection: Connection, password: String) async throws -> String {
        let delegate = HostKeyCaptureDelegate()

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandlers(
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: SimplePasswordDelegate(username: connection.username, password: password),
                            serverAuthDelegate: delegate
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    ),
                    NIOCloseOnErrorHandler()
                )
            }

        let channel = try await bootstrap.connect(host: connection.host, port: connection.port).get()
        let hostKey = try await delegate.hostKeyFuture.get()
        try? await channel.close()

        return SHA256HostKeyFingerprintFormatter.format(hostKey)
    }
}

public struct SHA256HostKeyFingerprintFormatter {
    public static func format(_ key: NIOSSHPublicKey) -> String {
        let openSSHString = String(openSSHPublicKey: key)
        print("[SSH] formatter: OpenSSH key string: \(openSSHString)")
        guard let base64Part = openSSHString.split(separator: " ").dropFirst().first,
              let rawData = Data(base64Encoded: String(base64Part)) else {
            return "SHA256:invalid-key"
        }
        let digest = SHA256.hash(data: rawData)
        let fp = "SHA256:" + Data(digest).base64EncodedString()
        print("[SSH] formatter: base64 length=\(base64Part.count), rawData length=\(rawData.count), fingerprint=\(fp)")
        return fp
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
