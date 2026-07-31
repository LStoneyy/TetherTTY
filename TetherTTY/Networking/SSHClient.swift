import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSH

struct SSHExecResult: Equatable {
    let stdout: String
    let stderr: String
    let exitStatus: Int
}

struct SSHShellRequest: Equatable {
    let host: String
    let port: Int
    let username: String
    let password: String
}

protocol SSHClient {
    func openShell(_ request: SSHShellRequest) async throws -> SSHSession
    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult
}

protocol SSHSession {
    var onOutput: (@Sendable ([UInt8]) -> Void)? { get set }
    var onDisconnect: (@Sendable () -> Void)? { get set }
    func send(_ bytes: [UInt8]) async throws
    func resize(cols: Int, rows: Int) async
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
    var executeHandler: ((SSHShellRequest, String) async throws -> SSHExecResult)?

    func openShell(_ request: SSHShellRequest) async throws -> SSHSession {
        try await Task.sleep(nanoseconds: 250_000_000)

        guard !request.password.isEmpty else {
            throw SSHClientError.missingPassword
        }

        return SimulatedSSHSession()
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        if let handler = executeHandler {
            return try await handler(request, command)
        }
        return SSHExecResult(stdout: "simulated output for: \(command)\n", stderr: "", exitStatus: 0)
    }
}

final class SimulatedSSHSession: SSHSession {
    var onOutput: (@Sendable ([UInt8]) -> Void)?
    var onDisconnect: (@Sendable () -> Void)?

    func send(_ bytes: [UInt8]) async throws {
        try await Task.sleep(nanoseconds: 80_000_000)
        let input = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        onOutput?(Array("\(input)\n(simulated ssh shell) command accepted\n".utf8))
    }

    func resize(cols: Int, rows: Int) async {}
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
            // TCP keepalive: NIOSSH 0.14.1 exposes no public SSH-level keepalive
            // (its global-request API is limited to TCP forwarding), so we rely on
            // TCP-level keepalive to bound detection of silently dropped links
            // (e.g. Wi-Fi -> cellular handoff) on the long-lived interactive shell
            // instead of hanging indefinitely.
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
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
            channel.eventLoop.execute {
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
                                allocator: childChannel.allocator,
                                cols: 80,
                                rows: 24
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
    }

    func execute(_ request: SSHShellRequest, command: String) async throws -> SSHExecResult {
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

        let result: SSHExecResult = try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let timeout = channel.eventLoop.scheduleTask(in: .seconds(8)) {
                guard !didResume else { return }
                didResume = true
                print("[SSH] execute: timed out waiting for channel")
                cont.resume(throwing: SSHClientError.connectionFailed("Command timed out"))
            }
            channel.eventLoop.execute {
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
    private var errorOutput = ByteBuffer()
    private let continuation: CheckedContinuation<SSHExecResult, Error>
    private var didResume = false

    init(command: String, continuation: CheckedContinuation<SSHExecResult, Error>, allocator: ByteBufferAllocator) {
        self.command = command
        self.continuation = continuation
        self.output = allocator.buffer(capacity: 4096)
        self.errorOutput = allocator.buffer(capacity: 1024)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: false),
            promise: nil
        )
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data else { return }
        switch channelData.type {
        case .channel:
            output.writeBuffer(&bytes)
        case .stdErr:
            errorOutput.writeBuffer(&bytes)
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exitStatus as SSHChannelRequestEvent.ExitStatus:
            guard !didResume else { return }
            didResume = true
            let result = SSHExecResult(
                stdout: String(buffer: output),
                stderr: String(buffer: errorOutput),
                exitStatus: exitStatus.exitStatus
            )
            continuation.resume(returning: result)
            context.close(promise: nil)
        case _ as SSHChannelRequestEvent.ExitSignal:
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: SSHExecResult(
                stdout: String(buffer: output),
                stderr: String(buffer: errorOutput),
                exitStatus: -1
            ))
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

final class InteractiveShellHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = Never

    private let continuation: CheckedContinuation<SSHSession, Error>
    private let allocator: ByteBufferAllocator
    private let initialCols: Int
    private let initialRows: Int
    private var didResume = false
    private weak var session: ShellChannelSession?

    init(continuation: CheckedContinuation<SSHSession, Error>, allocator: ByteBufferAllocator, cols: Int, rows: Int) {
        self.continuation = continuation
        self.allocator = allocator
        self.initialCols = cols
        self.initialRows = rows
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        guard let parentChannel = channel.parent else {
            guard !didResume else { return }
            didResume = true
            continuation.resume(throwing: SSHClientError.connectionFailed("Shell channel has no parent"))
            return
        }

        let session = ShellChannelSession(
            channel: channel,
            parentChannel: parentChannel,
            allocator: allocator
        )
        self.session = session

        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: initialCols,
                terminalRowHeight: initialRows,
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

        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: session)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let bytes) = channelData.data, bytes.readableBytes > 0 else { return }
        let chunk = Array(buffer: bytes)
        DispatchQueue.main.async { [weak self] in
            self?.session?.feedOutput(chunk)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exitStatus = event as? SSHChannelRequestEvent.ExitStatus {
            DispatchQueue.main.async { [weak self] in
                self?.session?.feedOutput(Array("[exit: \(exitStatus.exitStatus)]\n".utf8))
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        DispatchQueue.main.async { [weak self] in
            self?.session?.onDisconnect?()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !didResume {
            didResume = true
            continuation.resume(throwing: error)
        }
        context.close(promise: nil)
    }
}

final class ShellChannelSession: SSHSession {
    var onOutput: (@Sendable ([UInt8]) -> Void)? {
        didSet {
            guard let cb = onOutput, !pendingOutput.isEmpty else { return }
            let chunks = pendingOutput
            pendingOutput.removeAll()
            for chunk in chunks { cb(chunk) }
        }
    }
    var onDisconnect: (@Sendable () -> Void)?

    private let channel: Channel
    private let parentChannel: Channel
    private let allocator: ByteBufferAllocator
    private var pendingOutput: [[UInt8]] = []

    init(channel: Channel, parentChannel: Channel, allocator: ByteBufferAllocator) {
        self.channel = channel
        self.parentChannel = parentChannel
        self.allocator = allocator
    }

    func feedOutput(_ bytes: [UInt8]) {
        if let cb = onOutput {
            cb(bytes)
        } else {
            pendingOutput.append(bytes)
        }
    }

    func send(_ bytes: [UInt8]) async throws {
        var buffer = allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        try await channel.writeAndFlush(data)
    }

    func resize(cols: Int, rows: Int) async {
        guard cols > 0, rows > 0 else { return }
        channel.eventLoop.execute {
            let event = SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: cols,
                terminalRowHeight: rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0
            )
            self.channel.triggerUserOutboundEvent(event, promise: nil)
        }
    }

    func disconnect() async {
        try? await channel.close()
        try? await parentChannel.close()
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
