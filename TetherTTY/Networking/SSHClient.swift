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
    case hostKeyUnknown
    case hostKeyStoreError
    case outputLimitExceeded
    case executionTimedOut

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            "This tether has no stored password. Edit the connection and save a password before connecting."
        case .connectionFailed(let message):
            message
        case .hostKeyChanged(let expected, let actual):
            "Host key changed!\nExpected: \(expected)\nActual: \(actual)"
        case .hostKeyUnknown:
            "Host key is unknown and was not trusted before connecting. Refusing to connect."
        case .hostKeyStoreError:
            "Could not read the known-hosts store. Refusing to connect for safety."
        case .outputLimitExceeded:
            "The command produced more output than allowed and was stopped."
        case .executionTimedOut:
            "The command took too long to complete and was stopped."
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

        return try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let timeout = channel.eventLoop.scheduleTask(in: .seconds(8)) {
                guard !didResume else { return }
                didResume = true
                cont.resume(throwing: SSHClientError.connectionFailed("Shell channel setup timed out"))
            }
            channel.eventLoop.execute {
                sshHandler.createChannel { childChannel, channelType in
                    timeout.cancel()
                    guard !didResume else { return childChannel.close().map { _ in () } }
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

        let result: SSHExecResult = try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let timeout = channel.eventLoop.scheduleTask(in: .seconds(8)) {
                guard !didResume else { return }
                didResume = true
                cont.resume(throwing: SSHClientError.connectionFailed("Command timed out"))
            }
            channel.eventLoop.execute {
                sshHandler.createChannel { childChannel, channelType in
                    timeout.cancel()
                    guard !didResume else { return childChannel.close().map { _ in () } }
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            SSHClientError.connectionFailed("Unexpected channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        _ = childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                        do {
                            // SEC-05: bounds combined stdout+stderr output and enforces an overall
                            // exec deadline; both complete this continuation exactly once and
                            // guarantee the channel is closed (see ExecCommandHandler below).
                            try childChannel.pipeline.syncOperations.addHandler(
                                ExecCommandHandler(command: command, continuation: cont, allocator: childChannel.allocator)
                            )
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

/// Drives a single remote `exec` channel to completion.
///
/// SEC-05: this handler bounds two unbounded resources a hostile or misbehaving remote command
/// could otherwise exploit:
///  - **Output**: stdout+stderr are capped at a combined `outputLimit` (default 1 MiB). Exceeding
///    it completes with `.outputLimitExceeded` and closes the channel immediately instead of
///    continuing to buffer remote-controlled bytes in memory.
///  - **Time**: an overall `deadline` (default 15s) is scheduled on the channel's event loop when
///    the handler is added and is cancelled on every completion path, so a hung/slow-drip command
///    can't block the app indefinitely.
///
/// Every completion path (success, exit-signal, output-limit, timeout, transport error, or the
/// channel going inactive without ever reporting a result) funnels through `complete(...)`, which
/// uses the `didResume` guard to resume the continuation and close the channel EXACTLY ONCE. NIO
/// invokes channel-handler callbacks serially on a single event-loop thread, so this guard is
/// race-free without additional locking.
final class ExecCommandHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = Never
    typealias OutboundOut = SSHChannelData

    /// Combined stdout+stderr byte budget for a single exec invocation.
    static let defaultOutputLimit = 1_048_576 // 1 MiB

    /// Overall wall-clock budget for a single exec invocation (from handler-added to completion).
    static let defaultDeadline: TimeAmount = .seconds(15)

    private let command: String
    private var output = ByteBuffer()
    private var errorOutput = ByteBuffer()
    private var receivedBytes = 0
    private let outputLimit: Int
    private let deadline: TimeAmount
    private let continuation: CheckedContinuation<SSHExecResult, Error>
    private var didResume = false
    private var deadlineTask: Scheduled<Void>?

    init(
        command: String,
        continuation: CheckedContinuation<SSHExecResult, Error>,
        allocator: ByteBufferAllocator,
        outputLimit: Int = ExecCommandHandler.defaultOutputLimit,
        deadline: TimeAmount = ExecCommandHandler.defaultDeadline
    ) {
        self.command = command
        self.continuation = continuation
        self.output = allocator.buffer(capacity: 4096)
        self.errorOutput = allocator.buffer(capacity: 1024)
        self.outputLimit = outputLimit
        self.deadline = deadline
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: false),
            promise: nil
        )
        deadlineTask = context.eventLoop.scheduleTask(in: deadline) { [weak self] in
            self?.complete(context: context, result: .failure(SSHClientError.executionTimedOut))
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !didResume else { return }
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data else { return }

        let incoming = bytes.readableBytes
        guard receivedBytes + incoming <= outputLimit else {
            complete(context: context, result: .failure(SSHClientError.outputLimitExceeded))
            return
        }
        receivedBytes += incoming

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
            complete(context: context, result: .success(SSHExecResult(
                stdout: String(buffer: output),
                stderr: String(buffer: errorOutput),
                exitStatus: exitStatus.exitStatus
            )))
        case _ as SSHChannelRequestEvent.ExitSignal:
            complete(context: context, result: .success(SSHExecResult(
                stdout: String(buffer: output),
                stderr: String(buffer: errorOutput),
                exitStatus: -1
            )))
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        complete(context: context, result: .failure(error))
    }

    /// Defensive completion path: if the remote end drops the channel without ever sending an
    /// `ExitStatus`/`ExitSignal` (and we haven't already completed via output-limit/timeout/error),
    /// this ensures the continuation is still resumed instead of hanging forever.
    func channelInactive(context: ChannelHandlerContext) {
        complete(context: context, result: .failure(SSHClientError.connectionFailed("Command channel closed unexpectedly")))
        context.fireChannelInactive()
    }

    private func complete(context: ChannelHandlerContext, result: Result<SSHExecResult, Error>) {
        guard !didResume else { return }
        didResume = true
        deadlineTask?.cancel()
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
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
        guard availableMethods.contains(.password) else {
            nextChallengePromise.fail(SSHClientError.connectionFailed("Password authentication not available"))
            return
        }
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "ssh-connection",
            offer: .password(.init(password: password))
        ))
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
        do {
            if let knownHost = try knownHostStore.knownHost(host: host, port: port) {
                if knownHost.fingerprint == fingerprint {
                    validationCompletePromise.succeed(())
                } else {
                    validationCompletePromise.fail(SSHClientError.hostKeyChanged(expected: knownHost.fingerprint, actual: fingerprint))
                }
            } else {
                // Fail-closed: an unknown host must never be silently trusted here.
                // The higher-level TOFU flow (HostKeyTrustEvaluator + HostListViewModel)
                // is responsible for showing the fingerprint to the user and explicitly
                // persisting trust via KnownHostStore.trustHost(...) BEFORE this delegate
                // is ever asked to validate a real connect/shell attempt for that host.
                validationCompletePromise.fail(SSHClientError.hostKeyUnknown)
            }
        } catch {
            validationCompletePromise.fail(SSHClientError.hostKeyStoreError)
        }
    }
}

final class NIOCloseOnErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
