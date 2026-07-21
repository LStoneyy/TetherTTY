import XCTest
@testable import TetherTTY

final class HerdrSessionParserTests: XCTestCase {
    func testParsesRepresentativeOutput() {
        let output = """
        workspace\tprod\tactive\therdr enter workspace prod\tregion:us-east-1
        agent\tbuilder\tidle\therdr attach agent builder
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 2)

        XCTAssertEqual(sessions[0].displayName, "prod")
        XCTAssertEqual(sessions[0].detail, "workspace · active · region:us-east-1")
        if case .herdr(let kind, let name, let status, let attachCommand, let metadata) = sessions[0].provider {
            XCTAssertEqual(kind, "workspace")
            XCTAssertEqual(name, "prod")
            XCTAssertEqual(status, "active")
            XCTAssertEqual(attachCommand, "herdr enter workspace prod")
            XCTAssertEqual(metadata, "region:us-east-1")
        } else {
            XCTFail("Expected herdr session")
        }

        XCTAssertEqual(sessions[1].displayName, "builder")
        if case .herdr(let kind, let name, let status, let attachCommand, let metadata) = sessions[1].provider {
            XCTAssertEqual(kind, "agent")
            XCTAssertEqual(name, "builder")
            XCTAssertEqual(status, "idle")
            XCTAssertEqual(attachCommand, "herdr attach agent builder")
            XCTAssertNil(metadata)
        } else {
            XCTFail("Expected herdr session")
        }
    }

    func testParsesEmptyOutput() {
        let sessions = HerdrSessionParser.parse("")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParsesWhitespaceOnlyOutput() {
        let sessions = HerdrSessionParser.parse("   \n  \n  ")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSkipsMalformedRows() {
        let output = """
        workspace\tvalid\tactive\therdr enter valid
        not-enough-columns
        \t\t\t
        agent\tvalid2\tidle\therdr attach valid2\textra
        """

        let sessions = HerdrSessionParser.parse(output)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].displayName, "valid")
        XCTAssertEqual(sessions[1].displayName, "valid2")
    }

    func testSkipsRowWithEmptyKind() {
        let output = "\tname\tactive\tcommand"
        let sessions = HerdrSessionParser.parse(output)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSkipsRowWithEmptyName() {
        let output = "kind\t\tactive\tcommand"
        let sessions = HerdrSessionParser.parse(output)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSkipsRowWithEmptyAttachCommand() {
        let output = "kind\tname\tactive\t"
        let sessions = HerdrSessionParser.parse(output)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testStartupCommandForHerdrSession() {
        let session = TerminalSession(
            id: "herdr-workspace-prod",
            provider: .herdr(
                kind: "workspace",
                name: "prod",
                status: "active",
                attachCommand: "herdr enter workspace prod",
                metadata: nil
            ),
            displayName: "prod",
            detail: "workspace · active"
        )

        XCTAssertEqual(session.startupCommand, "herdr enter workspace prod")
    }

    func testStartupCommandForPlainShell() {
        XCTAssertNil(TerminalSession.plainShellSession.startupCommand)
    }
}
