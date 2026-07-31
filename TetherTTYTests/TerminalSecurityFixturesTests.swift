import XCTest
import UIKit
@testable import TetherTTY

/// Security regression fixtures for the terminal trust boundary (Phase 2):
/// OSC 52 clipboard blocking (SEC-03), https-only link allowlist (SEC-08),
/// and injection-safe typed startup actions (SEC-07).
final class TerminalSecurityFixturesTests: XCTestCase {

    // MARK: - SEC-03: OSC 52 clipboard write is a no-op

    @MainActor
    func testClipboardCopyIsNoOp() {
        let sentinel = "sentinel-\(UUID().uuidString)"
        UIPasteboard.general.string = sentinel

        let view = SSHTerminalView(frame: .zero)
        view.clipboardCopy(source: view, content: Data("attacker-controlled".utf8))

        XCTAssertEqual(
            UIPasteboard.general.string,
            sentinel,
            "clipboardCopy must not write remote content to the system pasteboard"
        )
    }

    // MARK: - SEC-08: only https:// links may open

    func testOnlyHttpsUrlsOpened() {
        let url = SSHTerminalView.allowedURL(forLink: "https://example.com/path")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path")
    }

    func testHttpsIsCaseInsensitive() {
        XCTAssertNotNil(SSHTerminalView.allowedURL(forLink: "HTTPS://example.com"))
    }

    func testHttpUrlsRejected() {
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "http://example.com"))
    }

    func testArbitrarySchemeRejected() {
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "file:///etc/passwd"))
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "javascript:alert(1)"))
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "tel:+15550000000"))
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "customscheme://do-something"))
        XCTAssertNil(SSHTerminalView.allowedURL(forLink: "not a url at all"))
    }

    // MARK: - SEC-07: typed startup action, POSIX quoting, control-char rejection

    func testStartupCommandQuotingNormalName() {
        let action = TerminalStartupAction.tmuxAttach(sessionName: "work")
        XCTAssertEqual(action.renderStartupCommand(), "tmux attach-session -t 'work'")
    }

    func testStartupCommandQuotingMetacharacters() {
        // A malicious session name with a single quote plus shell metacharacters
        // must be fully contained inside a single POSIX-quoted argument.
        let action = TerminalStartupAction.tmuxAttach(sessionName: "a'b; rm -rf ~")
        XCTAssertEqual(action.renderStartupCommand(), "tmux attach-session -t 'a'\\''b; rm -rf ~'")
    }

    func testStartupCommandRejectsNulCrLf() {
        XCTAssertNil(TerminalStartupAction.tmuxAttach(sessionName: "a\nb").renderStartupCommand())
        XCTAssertNil(TerminalStartupAction.tmuxAttach(sessionName: "a\rb").renderStartupCommand())
        XCTAssertNil(TerminalStartupAction.tmuxAttach(sessionName: "a\0b").renderStartupCommand())
        XCTAssertNil(TerminalStartupAction.herdrAttach(command: "herdr attach\nrm -rf ~").renderStartupCommand())
    }

    func testStartupCommandRejectsEmpty() {
        XCTAssertNil(TerminalStartupAction.tmuxAttach(sessionName: "").renderStartupCommand())
    }

    func testStartupCommandRejectsOverlongName() {
        let overlong = String(repeating: "x", count: TerminalStartupAction.maxTmuxSessionNameLength + 1)
        XCTAssertNil(TerminalStartupAction.tmuxAttach(sessionName: overlong).renderStartupCommand())
    }

    func testHerdrCommandPassesThroughWhenSafe() {
        let action = TerminalStartupAction.herdrAttach(command: "herdr session attach prod")
        XCTAssertEqual(action.renderStartupCommand(), "herdr session attach prod")
    }
}
