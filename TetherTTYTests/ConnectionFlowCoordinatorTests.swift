import XCTest
@testable import TetherTTY

@MainActor
final class ConnectionFlowCoordinatorTests: XCTestCase {
    private func makeConnection() -> Connection {
        Connection(alias: "Box", host: "box.local", port: 22, username: "lukas")
    }

    private func makeRequest(_ connection: Connection, startupAction: TerminalStartupAction? = nil) -> TerminalConnectionRequest {
        TerminalConnectionRequest(connection: connection, password: "pw", startupAction: startupAction)
    }

    func testStartWithTrustedHostGoesToPickingSession() async {
        let connection = makeConnection()
        let request = makeRequest(connection)
        let host = FakeConnectionFlowHost()
        host.requestResult = .trusted(request)
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()

        XCTAssertEqual(coordinator.phase, .pickingSession)
        XCTAssertEqual(coordinator.activeRequest?.id, request.id)
    }

    func testStartWithUnknownHostShowsInlineTrustPrompt() async {
        let connection = makeConnection()
        let challenge = HostKeyChallenge(connection: connection, fingerprint: "SHA256:new")
        let host = FakeConnectionFlowHost()
        host.requestResult = .unknown(challenge)
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()

        XCTAssertEqual(coordinator.phase, .trustPrompt(challenge))
        XCTAssertNil(coordinator.activeRequest)
    }

    func testStartWithChangedHostKeyFails() async {
        let connection = makeConnection()
        let host = FakeConnectionFlowHost()
        host.requestResult = .failed("Host key changed. Expected A, got B. Connection blocked.")
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()

        guard case .failed(let message) = coordinator.phase else {
            return XCTFail("Expected .failed, got \(coordinator.phase)")
        }
        XCTAssertTrue(message.contains("Host key changed"))
    }

    func testTrustCurrentHostAdvancesToPickingSession() async {
        let connection = makeConnection()
        let challenge = HostKeyChallenge(connection: connection, fingerprint: "SHA256:new")
        let request = makeRequest(connection)
        let host = FakeConnectionFlowHost()
        host.requestResult = .unknown(challenge)
        host.trustResult = request
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()
        XCTAssertEqual(coordinator.phase, .trustPrompt(challenge))

        coordinator.trustCurrentHost()

        XCTAssertEqual(coordinator.phase, .pickingSession)
        XCTAssertEqual(coordinator.activeRequest?.id, request.id)
    }

    func testTrustFailureShowsFailure() async {
        let connection = makeConnection()
        let challenge = HostKeyChallenge(connection: connection, fingerprint: "SHA256:new")
        let host = FakeConnectionFlowHost()
        host.requestResult = .unknown(challenge)
        host.trustResult = nil               // saving the host key failed
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()
        coordinator.trustCurrentHost()

        guard case .failed = coordinator.phase else {
            return XCTFail("Expected .failed, got \(coordinator.phase)")
        }
    }

    func testSelectSessionOpensTerminalWithChosenRequest() {
        let connection = makeConnection()
        let host = FakeConnectionFlowHost()
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        let chosen = makeRequest(connection, startupAction: .tmuxAttach(sessionName: "work"))
        coordinator.selectSession(chosen)

        XCTAssertEqual(coordinator.phase, .terminal)
        XCTAssertEqual(coordinator.activeRequest?.id, chosen.id)
        XCTAssertNotNil(coordinator.activeRequest?.startupAction)
    }

    func testRequestReconnectReturnsToPickingSession() {
        let connection = makeConnection()
        let host = FakeConnectionFlowHost()
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)
        coordinator.selectSession(makeRequest(connection, startupAction: .tmuxAttach(sessionName: "work")))
        XCTAssertEqual(coordinator.phase, .terminal)

        let reconnect = makeRequest(connection)
        coordinator.requestReconnect(reconnect)

        XCTAssertEqual(coordinator.phase, .pickingSession)
        XCTAssertEqual(coordinator.activeRequest?.id, reconnect.id)
        XCTAssertNil(coordinator.activeRequest?.startupAction)
    }

    func testRetryReturnsToVerifying() async {
        let connection = makeConnection()
        let host = FakeConnectionFlowHost()
        host.requestResult = .failed("Could not verify this tether's host key.")
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.start()
        await coordinator.awaitSettled()
        guard case .failed = coordinator.phase else {
            return XCTFail("Expected .failed before retry")
        }

        coordinator.retry()
        XCTAssertEqual(coordinator.phase, .verifyingHostKey, "Retry restarts verification")
    }

    func testCancelStopsWorkAndClearsHostState() {
        let connection = makeConnection()
        let host = FakeConnectionFlowHost()
        let coordinator = ConnectionFlowCoordinator(connection: connection, host: host)

        coordinator.cancel()

        XCTAssertTrue(host.cancelConnectCalled)
        XCTAssertTrue(host.cancelHostKeyTrustCalled)
    }
}

/// Scriptable stand-in for `HostListViewModel`, mirroring its contract: `terminalRequest` sets
/// `hostKeyChallenge`/`connectPhase` as side effects the coordinator reads to route the flow.
@MainActor
final class FakeConnectionFlowHost: ConnectionFlowHost {
    enum RequestResult {
        case trusted(TerminalConnectionRequest)
        case unknown(HostKeyChallenge)
        case failed(String)
    }

    var requestResult: RequestResult = .failed("unset")
    var trustResult: TerminalConnectionRequest?
    private(set) var cancelConnectCalled = false
    private(set) var cancelHostKeyTrustCalled = false

    var hostKeyChallenge: HostKeyChallenge?
    var connectPhase: ConnectionPhase?

    func terminalRequest(for connection: Connection) async -> TerminalConnectionRequest? {
        switch requestResult {
        case .trusted(let request):
            hostKeyChallenge = nil
            connectPhase = nil
            return request
        case .unknown(let challenge):
            hostKeyChallenge = challenge
            connectPhase = nil
            return nil
        case .failed(let message):
            hostKeyChallenge = nil
            connectPhase = .failed(message)
            return nil
        }
    }

    func trustHostKey(_ challenge: HostKeyChallenge) -> TerminalConnectionRequest? {
        trustResult
    }

    func cancelConnect() {
        cancelConnectCalled = true
        connectPhase = nil
    }

    func cancelHostKeyTrust() {
        cancelHostKeyTrustCalled = true
        hostKeyChallenge = nil
    }
}
