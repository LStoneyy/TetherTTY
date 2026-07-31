import XCTest
@testable import TetherTTY

final class HerdrSessionParserTests: XCTestCase {
    func testParsesRepresentativeJSONOutput() {
        let output = """
        [
          {"name": "default", "status": "attached"},
          {"name": "work", "state": "detached", "label": "feature work"}
        ]
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 2)

        XCTAssertEqual(sessions[0].displayName, "default")
        XCTAssertEqual(sessions[0].detail, "session · attached")
        if case .herdr(let kind, let name, let status, let attachCommand, let metadata) = sessions[0].provider {
            XCTAssertEqual(kind, "session")
            XCTAssertEqual(name, "default")
            XCTAssertEqual(status, "attached")
            XCTAssertEqual(attachCommand, "herdr session attach default")
            XCTAssertNil(metadata)
        } else {
            XCTFail("Expected herdr session")
        }

        XCTAssertEqual(sessions[1].displayName, "work")
        XCTAssertEqual(sessions[1].detail, "session · detached · feature work")
        if case .herdr(_, _, let status, _, let metadata) = sessions[1].provider {
            XCTAssertEqual(status, "detached")
            XCTAssertEqual(metadata, "feature work")
        } else {
            XCTFail("Expected herdr session")
        }
    }

    func testParsesJSONObjectWithSessionsKey() {
        let output = """
        {"sessions": [{"name": "alpha"}, {"name": "beta", "attached": true}]}
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.map(\.displayName), ["alpha", "beta"])
        if case .herdr(_, _, let status, _, _) = sessions[1].provider {
            XCTAssertEqual(status, "attached")
        } else {
            XCTFail("Expected herdr session")
        }
    }

    func testParsesJSONArrayOfStrings() {
        let output = """
        ["default", "ops"]
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.map(\.displayName), ["default", "ops"])
        XCTAssertEqual(sessions[0].startupAction?.renderStartupCommand(), "herdr session attach default")
    }

    func testParsesIdWhenNameMissing() {
        let output = """
        [{"id": "xyz", "status": "idle"}]
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].displayName, "xyz")
    }

    func testParsesEmptyOutput() {
        XCTAssertTrue(HerdrSessionParser.parse("").isEmpty)
    }

    func testParsesWhitespaceOnlyOutput() {
        XCTAssertTrue(HerdrSessionParser.parse("   \n  \n  ").isEmpty)
    }

    func testParsesEmptyJSONArray() {
        XCTAssertTrue(HerdrSessionParser.parse("[]").isEmpty)
    }

    func testNonJSONOutputYieldsEmpty() {
        XCTAssertTrue(HerdrSessionParser.parse("unknown command: list").isEmpty)
    }

    func testSkipsEntriesWithoutName() {
        let output = """
        [{"status": "active"}, {"name": "valid"}]
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].displayName, "valid")
    }

    func testSkipsEntriesWithEmptyName() {
        let output = """
        [{"name": ""}, {"name": "valid"}]
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].displayName, "valid")
    }

    func testStartupCommandForHerdrSession() {
        let session = TerminalSession(
            id: "herdr-session-prod",
            provider: .herdr(
                kind: "session",
                name: "prod",
                status: "attached",
                attachCommand: "herdr session attach prod",
                metadata: nil
            ),
            displayName: "prod",
            detail: "session · attached"
        )

        XCTAssertEqual(session.startupAction?.renderStartupCommand(), "herdr session attach prod")
    }

    func testStartupCommandForPlainShell() {
        XCTAssertNil(TerminalSession.plainShellSession.startupAction)
    }
}
