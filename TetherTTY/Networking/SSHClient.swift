import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSH

struct SSHShellRequest: Equatable {
    let host: String
    let port: Int
    let username: String
    let password: String
}

protocol SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession
    func execute(_ request: SSHShellRequest, command: String) async throws -> String
}

protocol SSHSession {
    var banner: String { get }
    func send(_ input: String) async throws -> String
    func disconnect() async
}

enum SSHClientError: LocalizedError, Equatable {
    case missingPassword
    case connectionFailed(String)
    case hostKeyChanged(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            "This tether has no stored password. Edit the connection and save a password before connecting."
        case .connectionFailed(let message):
            message
        case .hostKeyChanged(let expected, let actual):
            "Host key changed!\nExpected: \(expected)\nActual: \(actual)"
        }
    }
}

struct SimulatedSSHClient: SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        try await Task.sleep(nanoseconds: 250_000_000)

        guard !request.password.isEmpty else {
            throw SSHClientError.missingPassword
        }

        return SimulatedSSHSession(request: request)
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return "simulated output for: \(command)\n"
    }
}

final class SimulatedSSHSession: SSHSession {
    let banner: String
    private let prompt: String

    init(request: SSHShellRequest) {
        prompt = "\(request.username)@\(request.host)$"
        banner = "Connected to \(request.username)@\(request.host):\(request.port)\n\(prompt) "
    }

    func send(_ input: String) async throws -> String {
        try await Task.sleep(nanoseconds: 80_000_000)
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if command == "clear" {
            return "\(prompt) "
        }

        return "\(command)\n(simulated ssh shell) command accepted\n\(prompt) "
    }

    func disconnect() async {}
}

// MARK: - Real SSH Implementation

final class SwiftNIOSSHClient: SSHClient {
    private let group = NIOSingletons.posixEventLoopGroup
    private let knownHostStore: KnownHostStore

    init(knownHostStore: KnownHostStore = LocalKnownHostStore()) {
        self.knownHostStore = knownHostStore
    }

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        guard !request.password.isEmpty else {
            throw SSHClientError.missingPassword
        }

        print("[SSH] openShell connecting to \(request.host):\(request.port) as \(request.username)...")

        let handlerPromise = group.next().makePromise(of: NIOSSHHandler.self)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(8))
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: SimplePasswordDelegate(username: request.username, password: request.password),
                        serverAuthDelegate: VerifyingHostKeyDelegate(
                            knownHostStore: self.knownHostStore,
                            host: request.host,
                            port: request.port
                        )
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                handlerPromise.succeed(sshHandler)
                return channel.pipeline.addHandlers(sshHandler, NIOCloseOnErrorHandler())
            }

        let channel = try await bootstrap.connect(host: request.host, port: request.port).get()
        let sshHandler = try await handlerPromise.futureResult.get()

        print("[SSH] openShell: connected, creating shell channel...")

        return try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let timeout = channel.eventLoop.scheduleTask(in: .seconds(8)) {
                guard !didResume else { return }
                didResume = true
                print("[SSH] openShell: timed out waiting for channel")
                cont.resume(throwing: SSHClientError.connectionFailed("Shell channel setup timed out"))
            }
            sshHandler.createChannel { childChannel, channelType in
                timeout.cancel()
                guard !didResume else { return childChannel.close().map { _ in () } }
                print("[SSH] openShell: channel type=\(channelType)")
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(
                        SSHClientError.connectionFailed("Unexpected channel type")
                    )
                }
                return childChannel.eventLoop.makeCompletedFuture {
                    _ = childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                    do {
                        let shell = InteractiveShellHandler(
                            continuation: cont,
                            allocator: childChannel.allocator
                        )
                        try childChannel.pipeline.syncOperations.addHandler(shell)
                        print("[SSH] openShell: shell handler added")
                    } catch {
                        guard !didResume else { return }
                        didResume = true
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> String {
        guard !request.password.isEmpty else {
            throw SSHClientError.missingPassword
        }

        print("[SSH] execute '\(command)' on \(request.host):\(request.port) as \(request.username)...")

        let handlerPromise = group.next().makePromise(of: NIOSSHHandler.self)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(8))
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: SimplePasswordDelegate(username: request.username, password: request.password),
                        serverAuthDelegate: VerifyingHostKeyDelegate(
                            knownHostStore: self.knownHostStore,
                            host: request.host,
                            port: request.port
                        )
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                handlerPromise.succeed(sshHandler)
                return channel.pipeline.addHandlers(sshHandler, NIOCloseOnErrorHandler())
            }

        let channel = try await bootstrap.connect(host: request.host, port: request.port).get()
        let sshHandler = try await handlerPromise.futureResult.get()

        print("[SSH] execute: connected, creating exec channel...")

        let result: String = try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let timeout = channel.eventLoop.scheduleTask(in: .seconds(8)) {
                guard !didResume else { return }
                didResume = true
                print("[SSH] execute: timed out waiting for channel")
                cont.resume(throwing: SSHClientError.connectionFailed("Command timed out"))
            }
            sshHandler.createChannel { childChannel, channelType in
                timeout.cancel()
                guard !didResume else { return childChannel.close().map { _ in () } }
                print("[SSH] execute: channel type=\(channelType)")
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(
                        SSHClientError.connectionFailed("Unexpected channel type")
                    )
                }
                return childChannel.eventLoop.makeCompletedFuture {
                    _ = childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                    do {
                        try childChannel.pipeline.syncOperations.addHandler(
                            ExecCommandHandler(command: command, continuation: cont, allocator: childChannel.allocator)
                        )
                        print("[SSH] execute: exec handler added")
                    } catch {
                        guard !didResume else { return }
                        didResume = true
                        cont.resume(throwing: error)
                    }
                }
            }
        }

        try? await channel.close()
        return result
    }
}

// MARK: - Exec Command Handler

final class ExecCommandHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = Never
    typealias OutboundOut = SSHChannelData

    private let command: String
    private var output = ByteBuffer()
    private let continuation: CheckedContinuation<String, Error>
    private var didResume = false

    init(command: String, continuation: CheckedContinuation<String, Error>, allocator: ByteBufferAllocator) {
        self.command = command
        self.continuation = continuation
        self.output = allocator.buffer(capacity: 4096)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: false),
            promise: nil
        )
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data, channelData.type == .channel else { return }
        output.writeBuffer(&bytes)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case _ as SSHChannelRequestEvent.ExitStatus, _ as SSHChannelRequestEvent.ExitSignal:
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: String(buffer: output))
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
        context.close(promise: nil)
    }
}

// MARK: - Interactive Shell Handler

final actor ShellOutputActor {
    private var buffer = ""
    func append(_ text: String) { buffer += text }
    func drain() -> String { let b = buffer; buffer = ""; return b }
}

final class InteractiveShellHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = Never

    private let continuation: CheckedContinuation<SSHSession, Error>
    private let allocator: ByteBufferAllocator
    private let outputActor = ShellOutputActor()
    private var didResume = false

    init(continuation: CheckedContinuation<SSHSession, Error>, allocator: ByteBufferAllocator) {
        self.continuation = continuation
        self.allocator = allocator
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: 80,
                terminalRowHeight: 24,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            ),
            promise: nil
        )

        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ShellRequest(wantReply: true),
            promise: nil
        )

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !self.didResume else { return }
            self.didResume = true
            let initial = await self.outputActor.drain()
            let session = ShellChannelSession(
                channel: context.channel,
                parentChannel: context.channel.parent!,
                allocator: self.allocator,
                outputActor: self.outputActor,
                banner: initial
            )
            self.continuation.resume(returning: session)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let bytes) = channelData.data else { return }
        Task { await outputActor.append(String(buffer: bytes)) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
        context.close(promise: nil)
    }
}

final class ShellChannelSession: SSHSession {
    let banner: String
    private var channel: Channel?
    private var parentChannel: Channel?
    private let allocator: ByteBufferAllocator
    private let outputActor: ShellOutputActor

    init(channel: Channel, parentChannel: Channel, allocator: ByteBufferAllocator, outputActor: ShellOutputActor, banner: String) {
        self.channel = channel
        self.parentChannel = parentChannel
        self.allocator = allocator
        self.outputActor = outputActor
        self.banner = banner
    }

    func send(_ input: String) async throws -> String {
        guard let channel = channel else {
            throw SSHClientError.connectionFailed("Session closed")
        }

        let data = SSHChannelData(
            type: .channel,
            data: .byteBuffer(allocator.buffer(string: input + "\n"))
        )
        try await channel.writeAndFlush(data)
        try await Task.sleep(nanoseconds: 400_000_000)
        return await outputActor.drain()
    }

    func disconnect() async {
        try? await channel?.close()
        channel = nil
        try? await parentChannel?.close()
        parentChannel = nil
    }
}

// MARK: - Authentication Delegates

final class SimplePasswordDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        print("[SSH] auth: server offers methods \(availableMethods)")
        guard availableMethods.contains(.password) else {
            print("[SSH] auth: password not available")
            nextChallengePromise.fail(SSHClientError.connectionFailed("Password authentication not available"))
            return
        }
        print("[SSH] auth: sending password for \(username)")
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "ssh-connection",
            offer: .password(.init(password: password))
        ))
    }
}

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

final class VerifyingHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    let knownHostStore: KnownHostStore
    let host: String
    let port: Int

    init(knownHostStore: KnownHostStore, host: String, port: Int) {
        self.knownHostStore = knownHostStore
        self.host = host
        self.port = port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = SHA256HostKeyFingerprintFormatter.format(hostKey)
        print("[SSH] hostkey: fingerprint=\(fingerprint)")
        do {
            if let knownHost = try knownHostStore.knownHost(host: host, port: port) {
                if knownHost.fingerprint == fingerprint {
                    print("[SSH] hostkey: known and matches")
                    validationCompletePromise.succeed(())
                } else {
                    print("[SSH] hostkey: MISMATCH expected=\(knownHost.fingerprint) actual=\(fingerprint)")
                    validationCompletePromise.fail(SSHClientError.hostKeyChanged(expected: knownHost.fingerprint, actual: fingerprint))
                }
            } else {
                validationCompletePromise.succeed(())
            }
        } catch {
            validationCompletePromise.succeed(())
        }
    }
}

final class NIOCloseOnErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SSH] channel error: \(error)")
        context.close(promise: nil)
    }
}
