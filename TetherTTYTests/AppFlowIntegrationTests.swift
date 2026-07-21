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
            hostKeyTrustEvaluator: hostKeyEvaluator
        )

        XCTAssertEqual(hostListVM.connections.count, 1)
        XCTAssertEqual(hostListVM.connections.first?.alias, "Dev Machine")
        XCTAssertTrue(hostListVM.hasPassword(for: connection))

        let terminalRequest = hostListVM.terminalRequest(for: connection)
        XCTAssertNil(terminalRequest)
        XCTAssertNotNil(hostListVM.hostKeyChallenge)
        XCTAssertEqual(hostListVM.hostKeyChallenge?.connection.id, connection.id)
        XCTAssertEqual(hostListVM.hostKeyChallenge?.password, "secret")
        XCTAssertEqual(hostListVM.hostKeyChallenge?.fingerprint, "SHA256:test-fp")

        guard let trustedRequest = hostListVM.trustHostKey(hostListVM.hostKeyChallenge!) else {
            XCTFail("Expected trust to succeed")
            return
        }
        XCTAssertEqual(trustedRequest.connection.id, connection.id)
        XCTAssertEqual(trustedRequest.password, "secret")
        XCTAssertNil(trustedRequest.startupCommand)
        XCTAssertNil(hostListVM.hostKeyChallenge)

        let sessionPickerVM = SessionPickerViewModel(
            request: trustedRequest,
            tmuxProvider: SimulatedTmuxSessionProvider(),
            herdrProvider: SimulatedHerdrSessionProvider()
        )

        XCTAssertTrue(sessionPickerVM.isLoading)
        XCTAssertTrue(sessionPickerVM.sessions.isEmpty)
        XCTAssertNil(sessionPickerVM.errorMessage)

        await sessionPickerVM.fetchSessions()

        XCTAssertFalse(sessionPickerVM.isLoading)
        XCTAssertNil(sessionPickerVM.errorMessage)
        XCTAssertEqual(sessionPickerVM.sessions.count, 5)

        let tmuxSessions = sessionPickerVM.sessions.filter {
            if case .tmux = $0.provider { return true }
            return false
        }
        XCTAssertEqual(tmuxSessions.count, 2)
        XCTAssertEqual(tmuxSessions.first?.displayName, "shell")

        let herdrSessions = sessionPickerVM.sessions.filter {
            if case .herdr = $0.provider { return true }
            return false
        }
        XCTAssertEqual(herdrSessions.count, 2)
        XCTAssertEqual(herdrSessions.first?.displayName, "prod")

        guard let tmuxSession = tmuxSessions.first else {
            XCTFail("Expected at least one tmux session")
            return
        }

        let sessionRequest = sessionPickerVM.makeTerminalRequest(for: tmuxSession)
        XCTAssertEqual(sessionRequest.connection.id, connection.id)
        XCTAssertEqual(sessionRequest.startupCommand, "tmux attach-session -t shell")

        let terminalVM = PlainTerminalViewModel(
            request: sessionRequest,
            sshClient: StubSSHClient(session: StubSSHSession())
        )

        XCTAssertEqual(terminalVM.state, TerminalConnectionState.idle)
        XCTAssertTrue(terminalVM.transcript.isEmpty)

        await terminalVM.connect()

        XCTAssertEqual(terminalVM.state, TerminalConnectionState.terminalOpen)
        XCTAssertTrue(terminalVM.transcript.contains("tmux attach-session -t shell"))

        terminalVM.input = "ls -la"
        await terminalVM.sendCurrentInput()
        XCTAssertTrue(terminalVM.transcript.contains("ls -la"))
        XCTAssertTrue(terminalVM.transcript.contains("stub output for ls -la"))
        XCTAssertEqual(terminalVM.input, "")

        await terminalVM.disconnect()
        XCTAssertEqual(terminalVM.state, TerminalConnectionState.disconnected)
        XCTAssertTrue(terminalVM.transcript.contains("[disconnected]"))

        let reconnectRequest = terminalVM.makeReconnectRequest()
        XCTAssertEqual(reconnectRequest.connection.id, connection.id)
        XCTAssertEqual(reconnectRequest.password, "secret")
        XCTAssertNil(reconnectRequest.startupCommand)
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
            hostKeyTrustEvaluator: hostKeyEvaluator
        )

        let request = hostListVM.terminalRequest(for: connection)
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
            hostKeyTrustEvaluator: hostKeyEvaluator
        )

        let request = hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertEqual(hostListVM.errorMessage, SSHClientError.missingPassword.localizedDescription)
    }
}
