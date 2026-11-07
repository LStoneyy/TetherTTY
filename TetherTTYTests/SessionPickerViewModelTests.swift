import XCTest
@testable import TetherTTY

@MainActor
final class SessionPickerViewModelTests: XCTestCase {
    private func makeRequest() -> TerminalConnectionRequest {
        TerminalConnectionRequest(
            connection: Connection(alias: "Test", host: "test.local", username: "lukas"),
            password: "secret"
        )
    }

    func testNotInstalledOutcomeSetsFlagWithoutDiagnostic() async {
        let request = makeRequest()
        let viewModel = SessionPickerViewModel(
            request: request,
            tmuxProvider: StubTmuxSessionProvider(result: .success(([], .notInstalled))),
            herdrProvider: StubHerdrSessionProvider(result: .success(([], .notInstalled)))
        )

        await viewModel.fetchSessions()

        XCTAssertTrue(viewModel.tmuxNotInstalled)
        XCTAssertTrue(viewModel.herdrNotInstalled)
        XCTAssertNil(viewModel.tmuxDiagnostic)
        XCTAssertNil(viewModel.herdrDiagnostic)
        XCTAssertTrue(viewModel.tmuxSessions.isEmpty)
        XCTAssertTrue(viewModel.herdrSessions.isEmpty)
    }

    func testDiagnosticOutcomeSetsMessageWithoutNotInstalledFlag() async {
        let request = makeRequest()
        let viewModel = SessionPickerViewModel(
            request: request,
            tmuxProvider: StubTmuxSessionProvider(result: .success(([], .diagnostic("tmux exited 2")))),
            herdrProvider: StubHerdrSessionProvider(result: .success(([], .diagnostic("herdr exited 2"))))
        )

        await viewModel.fetchSessions()

        XCTAssertFalse(viewModel.tmuxNotInstalled)
        XCTAssertFalse(viewModel.herdrNotInstalled)
        XCTAssertEqual(viewModel.tmuxDiagnostic, "tmux exited 2")
        XCTAssertEqual(viewModel.herdrDiagnostic, "herdr exited 2")
    }

    func testOkOutcomeLeavesDiagnosticsAndNotInstalledClear() async {
        let request = makeRequest()
        let viewModel = SessionPickerViewModel(
            request: request,
            tmuxProvider: StubTmuxSessionProvider(result: .success(([], .ok))),
            herdrProvider: StubHerdrSessionProvider(result: .success(([], .ok)))
        )

        await viewModel.fetchSessions()

        XCTAssertFalse(viewModel.tmuxNotInstalled)
        XCTAssertFalse(viewModel.herdrNotInstalled)
        XCTAssertNil(viewModel.tmuxDiagnostic)
        XCTAssertNil(viewModel.herdrDiagnostic)
    }

    func testMixedOutcomesAreTrackedIndependently() async {
        let request = makeRequest()
        let viewModel = SessionPickerViewModel(
            request: request,
            tmuxProvider: StubTmuxSessionProvider(result: .success(([], .notInstalled))),
            herdrProvider: StubHerdrSessionProvider(result: .success(([], .diagnostic("herdr exited 2"))))
        )

        await viewModel.fetchSessions()

        XCTAssertTrue(viewModel.tmuxNotInstalled)
        XCTAssertFalse(viewModel.herdrNotInstalled)
        XCTAssertNil(viewModel.tmuxDiagnostic)
        XCTAssertEqual(viewModel.herdrDiagnostic, "herdr exited 2")
    }

    func testRefetchClearsStaleNotInstalledAndDiagnosticState() async {
        let request = makeRequest()
        let tmuxProvider = StubTmuxSessionProvider(result: .success(([], .notInstalled)))
        let herdrProvider = StubHerdrSessionProvider(result: .success(([], .diagnostic("herdr exited 2"))))
        let viewModel = SessionPickerViewModel(
            request: request,
            tmuxProvider: tmuxProvider,
            herdrProvider: herdrProvider
        )

        await viewModel.fetchSessions()
        XCTAssertTrue(viewModel.tmuxNotInstalled)
        XCTAssertEqual(viewModel.herdrDiagnostic, "herdr exited 2")

        tmuxProvider.result = .success(([], .ok))
        herdrProvider.result = .success(([], .ok))
        await viewModel.fetchSessions()

        XCTAssertFalse(viewModel.tmuxNotInstalled)
        XCTAssertNil(viewModel.herdrDiagnostic)
    }
}

private final class StubTmuxSessionProvider: TmuxSessionProvider {
    var result: Result<([TerminalSession], SessionDiscoveryOutcome), Error>

    init(result: Result<([TerminalSession], SessionDiscoveryOutcome), Error>) {
        self.result = result
    }

    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome) {
        let value = try result.get()
        return (value.0, value.1)
    }
}

private final class StubHerdrSessionProvider: HerdrSessionProvider {
    var result: Result<([TerminalSession], SessionDiscoveryOutcome), Error>

    init(result: Result<([TerminalSession], SessionDiscoveryOutcome), Error>) {
        self.result = result
    }

    func fetchSessions(for request: TerminalConnectionRequest) async throws -> (sessions: [TerminalSession], outcome: SessionDiscoveryOutcome) {
        let value = try result.get()
        return (value.0, value.1)
    }
}
