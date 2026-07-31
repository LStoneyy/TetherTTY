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
            hostKeyTrustEvaluator: hostKeyEvaluator
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
            hostKeyTrustEvaluator: hostKeyEvaluator
        )

        let request = await hostListVM.terminalRequest(for: connection)
        XCTAssertNil(request)
        XCTAssertEqual(hostListVM.errorMessage, SSHClientError.missingPassword.localizedDescription)
    }
}
