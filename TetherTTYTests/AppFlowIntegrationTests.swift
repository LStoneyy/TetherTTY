import XCTest
@testable import TetherTTY

@MainActor
final class AppFlowIntegrationTests: XCTestCase {
    private var repository: LocalConnectionRepository!
    private var credentialStore: InMemoryCredentialStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppFlowIntegrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        credentialStore = InMemoryCredentialStore()
        repository = LocalConnectionRepository(defaults: defaults, credentialStore: credentialStore)
        // Mark the one-time known-hosts migration as already done in this test's isolated
        // defaults, so constructing a HostListViewModel does not wipe an injected known-host
        // store (which would otherwise make host-key tests order-dependent on a fresh simulator).
        defaults.set(true, forKey: "known-hosts-migrated-to-real-v1")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        repository = nil
        credentialStore = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFullAppFlowUnlockThroughTerminalOpen() async throws {
        let connection = Connection(
            alias: "Dev Machine",
            host: "dev.local",
            port: 2222,
            username: "lukas"
        )
        try repository.saveConnection(connection, password: "secret")
        XCTAssertTrue(repository.hasPassword(for: connection.id))

        let knownHostStore = InMemoryKnownHostStore()
        let hostKeyEvaluator = HostKeyTrustEvaluator(
            knownHostStore: knownHostStore,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:test-fp")
        )
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: hostKeyEvaluator,
            migrationDefaults: defaults
        )

        XCTAssertEqual(hostListVM.connections.count, 1)
        XCTAssertEqual(hostListVM.connections.first?.alias, "Dev Machine")
        XCTAssertTrue(hostListVM.hasPassword(for: connection))

        let terminalRequest = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(terminalRequest)
        XCTAssertNotNil(hostListVM.hostKeyChallenge)
        XCTAssertEqual(hostListVM.hostKeyChallenge?.connection.id, connection.id)
        XCTAssertEqual(hostListVM.hostKeyChallenge?.fingerprint, "SHA256:test-fp")

        guard let trustedRequest = hostListVM.trustHostKey(hostListVM.hostKeyChallenge!) else {
            XCTFail("Expected trust to succeed")
            return
        }
        XCTAssertEqual(trustedRequest.connection.id, connection.id)
        XCTAssertEqual(trustedRequest.password, "secret")
        XCTAssertNil(trustedRequest.startupAction)
        XCTAssertNil(hostListVM.hostKeyChallenge)

        let sessionPickerVM = SessionPickerViewModel(
            request: trustedRequest,
            tmuxProvider: SimulatedTmuxSessionProvider(),
            herdrProvider: SimulatedHerdrSessionProvider()
        )

        XCTAssertTrue(sessionPickerVM.isLoading)
        XCTAssertTrue(sessionPickerVM.tmuxSessions.isEmpty)
        XCTAssertTrue(sessionPickerVM.herdrSessions.isEmpty)
        XCTAssertNil(sessionPickerVM.errorMessage)
        XCTAssertNil(sessionPickerVM.tmuxDiagnostic)
        XCTAssertNil(sessionPickerVM.herdrDiagnostic)

        await sessionPickerVM.fetchSessions()

        XCTAssertFalse(sessionPickerVM.isLoading)
        XCTAssertNil(sessionPickerVM.errorMessage)
        XCTAssertNil(sessionPickerVM.tmuxDiagnostic)
        XCTAssertNil(sessionPickerVM.herdrDiagnostic)
        XCTAssertEqual(sessionPickerVM.sessions.count, 5)
        XCTAssertEqual(sessionPickerVM.tmuxSessions.count, 2)
        XCTAssertEqual(sessionPickerVM.herdrSessions.count, 2)

        XCTAssertEqual(sessionPickerVM.tmuxSessions.first?.displayName, "shell")
        XCTAssertEqual(sessionPickerVM.herdrSessions.first?.displayName, "prod")

        guard let tmuxSession = sessionPickerVM.tmuxSessions.first else {
            XCTFail("Expected at least one tmux session")
            return
        }

        let sessionRequest = sessionPickerVM.makeTerminalRequest(for: tmuxSession)
        XCTAssertEqual(sessionRequest.connection.id, connection.id)
        XCTAssertEqual(sessionRequest.startupAction?.renderStartupCommand(), "tmux attach-session -t 'shell'")

        let stubSession = StubSSHSession()
        let terminalVM = PlainTerminalViewModel(
            request: sessionRequest,
            sshClient: StubSSHClient(session: stubSession)
        )

        XCTAssertEqual(terminalVM.state, TerminalConnectionState.idle)

        await terminalVM.connect()

        XCTAssertEqual(terminalVM.state, TerminalConnectionState.terminalOpen)
        XCTAssertNotNil(terminalVM.session)

        let expectedStartup = Array("tmux attach-session -t 'shell'\n".utf8)
        XCTAssertEqual(stubSession.sentBytes, expectedStartup)

        await terminalVM.disconnect()
        XCTAssertEqual(terminalVM.state, TerminalConnectionState.disconnected)
        XCTAssertNil(terminalVM.session)

        let reconnectRequest = terminalVM.makeReconnectRequest()
        XCTAssertEqual(reconnectRequest.connection.id, connection.id)
        XCTAssertEqual(reconnectRequest.password, "secret")
        XCTAssertNil(reconnectRequest.startupAction)
    }

    func testAppFlowWithHostKeyChangedBlocksConnection() async throws {
        let connection = Connection(alias: "Changed", host: "changed.local", username: "lukas")
        try repository.saveConnection(connection, password: "pass")

        let knownHostStore = InMemoryKnownHostStore()
        try knownHostStore.trustHost(host: "changed.local", port: 22, fingerprint: "SHA256:original")

        let hostKeyEvaluator = HostKeyTrustEvaluator(
            knownHostStore: knownHostStore,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:different")
        )
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: hostKeyEvaluator,
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertNotNil(hostListVM.errorMessage)
        XCTAssertTrue(hostListVM.errorMessage?.contains("Host key changed") ?? false)
    }

    func testAppFlowWithNoStoredPasswordShowsError() async throws {
        let connection = Connection(alias: "No Pass", host: "nopass.local", username: "lukas")
        try repository.saveConnection(connection, password: nil)

        let knownHostStore = InMemoryKnownHostStore()
        let hostKeyEvaluator = HostKeyTrustEvaluator(
            knownHostStore: knownHostStore,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:fp")
        )
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: hostKeyEvaluator,
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertEqual(hostListVM.errorMessage, SSHClientError.missingPassword.localizedDescription)
    }

    // MARK: - connectPhase (progress overlay) transitions

    func testConnectPhaseClearsOnTrustedHost() async throws {
        let connection = Connection(alias: "Known", host: "known.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        let knownHostStore = InMemoryKnownHostStore()
        try knownHostStore.trustHost(host: connection.host, port: connection.port, fingerprint: "SHA256:known-fp")
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: knownHostStore,
                fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:known-fp")
            ),
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNotNil(request)
        XCTAssertNil(hostListVM.connectPhase, "Overlay should hand off to the session picker on a trusted host")
    }

    func testConnectPhaseClearsForTrustPromptOnUnknownHost() async throws {
        let connection = Connection(alias: "New", host: "new.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: InMemoryKnownHostStore(),
                fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:fp")
            ),
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertNil(hostListVM.connectPhase, "Overlay should clear so the trust prompt takes over")
        XCTAssertNotNil(hostListVM.hostKeyChallenge)
    }

    func testConnectPhaseFailsOnChangedHostKey() async throws {
        let connection = Connection(alias: "Changed", host: "changed.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        let knownHostStore = InMemoryKnownHostStore()
        try knownHostStore.trustHost(host: connection.host, port: connection.port, fingerprint: "SHA256:original")
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: knownHostStore,
                fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:different")
            ),
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        guard case .failed(let message)? = hostListVM.connectPhase else {
            return XCTFail("Expected .failed phase, got \(String(describing: hostListVM.connectPhase))")
        }
        XCTAssertTrue(message.contains("Host key changed"))
    }

    func testConnectPhaseFailsWhenNoPassword() async throws {
        let connection = Connection(alias: "NoPass", host: "nopass.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: nil)

        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: InMemoryKnownHostStore(),
                fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:fp")
            ),
            migrationDefaults: defaults
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertEqual(hostListVM.connectPhase, .failed(SSHClientError.missingPassword.localizedDescription))
    }

    func testCancelConnectClearsPhaseAndInvalidatesAttempt() async throws {
        let connection = Connection(alias: "NoPass2", host: "nopass2.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: nil)

        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: InMemoryKnownHostStore(),
                fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:fp")
            ),
            migrationDefaults: defaults
        )

        _ = await hostListVM.terminalRequest(for: connection)
        XCTAssertNotNil(hostListVM.connectPhase)

        hostListVM.cancelConnect()
        XCTAssertNil(hostListVM.connectPhase)
    }

    func testCancelDuringCaptureDropsLateResult() async throws {
        let connection = Connection(alias: "Slow", host: "slow.local", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        // Unknown host: if the late result were applied it would raise a trust prompt and clear the
        // phase — exactly what the generation token must prevent after a cancel.
        let resolver = GatedFingerprintResolver(fingerprint: "SHA256:late-fp")
        let hostListVM = HostListViewModel(
            repository: repository,
            hostKeyTrustEvaluator: HostKeyTrustEvaluator(
                knownHostStore: InMemoryKnownHostStore(),
                fingerprintResolver: resolver
            ),
            migrationDefaults: defaults
        )

        let inFlight = Task { await hostListVM.terminalRequest(for: connection) }
        await resolver.waitUntilStarted()
        XCTAssertEqual(hostListVM.connectPhase, .verifyingHostKey)

        hostListVM.cancelConnect()          // invalidate the attempt while the capture is suspended
        resolver.release()                  // now let the stale capture finish
        let request = await inFlight.value

        XCTAssertNil(request)
        XCTAssertNil(hostListVM.connectPhase, "Late capture result must not reopen the overlay after cancel")
        XCTAssertNil(hostListVM.hostKeyChallenge, "A superseded attempt must not raise a trust prompt")
    }
}

/// A fingerprint resolver whose `fingerprint(for:)` blocks until `release()` is called, so a test
/// can cancel a connect attempt while the host-key capture is still in flight.
final class GatedFingerprintResolver: HostKeyFingerprintResolver, @unchecked Sendable {
    private let value: String
    private let lock = NSLock()
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var isReleased = false

    init(fingerprint: String) { self.value = fingerprint }

    func fingerprint(for connection: Connection) async throws -> String {
        lock.lock()
        hasStarted = true
        let started = startedContinuation
        startedContinuation = nil
        lock.unlock()
        started?.resume()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isReleased {
                lock.unlock()
                continuation.resume()
                return
            }
            releaseContinuation = continuation
            lock.unlock()
        }
        return value
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if hasStarted {
                lock.unlock()
                continuation.resume()
                return
            }
            startedContinuation = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        isReleased = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
