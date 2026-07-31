import XCTest
@testable import TetherTTY

/// Fixture tests for Phase 5 of the security remediation ("Input- und Data-Hardening"):
/// - Connection draft fields are length-limited, control-character-free, and scheme-prefix-free.
/// - The host is normalized to a canonical form (lowercased, single trailing dot stripped)
///   without mangling IPv4/IPv6 literals.
/// - Editing an existing connection's endpoint (host or port) removes the stale known-host pin
///   for the OLD host:port, while editing a non-endpoint field (e.g. alias) leaves it alone.
@MainActor
final class InputValidationSecurityTests: XCTestCase {
    private var repository: LocalConnectionRepository!
    private var credentialStore: InMemoryCredentialStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "InputValidationSecurityTests-\(UUID().uuidString)"
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

    private func draft(
        host: String = "example.com",
        port: String = "22",
        username: String = "user",
        alias: String = "Alias"
    ) -> ConnectionDraft {
        var draft = ConnectionDraft()
        draft.host = host
        draft.port = port
        draft.username = username
        draft.alias = alias
        return draft
    }

    // MARK: - Length validation

    func testHostLengthValidation() {
        let tooLong = String(repeating: "a", count: 254)
        let maxLength = String(repeating: "a", count: 253)

        XCTAssertFalse(draft(host: tooLong).isValid, "host longer than 253 chars must be rejected")
        XCTAssertTrue(draft(host: maxLength).isValid, "host of exactly 253 chars must be accepted")
    }

    func testUsernameLengthValidation() {
        let tooLong = String(repeating: "u", count: 257)
        let maxLength = String(repeating: "u", count: 256)

        XCTAssertFalse(draft(username: tooLong).isValid, "username longer than 256 chars must be rejected")
        XCTAssertTrue(draft(username: maxLength).isValid, "username of exactly 256 chars must be accepted")
    }

    func testAliasLengthValidation() {
        let tooLong = String(repeating: "a", count: 101)
        let maxLength = String(repeating: "a", count: 100)

        XCTAssertFalse(draft(alias: tooLong).isValid, "alias longer than 100 chars must be rejected")
        XCTAssertTrue(draft(alias: maxLength).isValid, "alias of exactly 100 chars must be accepted")
    }

    // MARK: - Control characters

    func testControlCharacterRejection() {
        for badChar in ["\n", "\r", "\t", "\0"] {
            XCTAssertFalse(
                draft(host: "example\(badChar)com").isValid,
                "host containing \(badChar.debugDescription) must be rejected"
            )
            XCTAssertFalse(
                draft(username: "user\(badChar)name").isValid,
                "username containing \(badChar.debugDescription) must be rejected"
            )
            XCTAssertFalse(
                draft(alias: "alias\(badChar)name").isValid,
                "alias containing \(badChar.debugDescription) must be rejected"
            )
        }
    }

    // MARK: - Scheme prefix rejection

    func testProtocolPrefixRejection() {
        for prefix in ["ssh://", "http://", "https://", "sftp://", "SSH://"] {
            XCTAssertFalse(
                draft(host: "\(prefix)example.com").isValid,
                "host with \(prefix) scheme prefix must be rejected"
            )
        }
    }

    // MARK: - Whitespace-only / trimming

    func testWhitespaceOnlyRejected() {
        XCTAssertFalse(draft(host: "   ").isValid, "whitespace-only host must be rejected")
        XCTAssertFalse(draft(username: "   ").isValid, "whitespace-only username must be rejected")

        let padded = draft(host: "  example.com  ", username: "  user  ")
        XCTAssertTrue(padded.isValid)
        XCTAssertEqual(padded.connection.host, "example.com")
        XCTAssertEqual(padded.connection.username, "user")
    }

    // MARK: - Host normalization

    func testHostNormalization() {
        let normalized = draft(host: "Example.COM.")
        XCTAssertTrue(normalized.isValid)
        XCTAssertEqual(normalized.connection.host, "example.com")
    }

    func testIPv6NotMangled() {
        let bare = draft(host: "2001:db8::1")
        XCTAssertTrue(bare.isValid)
        XCTAssertEqual(bare.connection.host, "2001:db8::1")

        let bracketed = draft(host: "[2001:DB8::1]")
        XCTAssertTrue(bracketed.isValid)
        XCTAssertEqual(bracketed.connection.host, "[2001:db8::1]")
    }

    // MARK: - Known-host pin cleanup on endpoint change

    func testKnownHostRemovedOnHostChange() throws {
        let connection = Connection(alias: "Box", host: "old.example.com", port: 22, username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        let knownHostStore = InMemoryKnownHostStore()
        try knownHostStore.trustHost(host: "old.example.com", port: 22, fingerprint: "SHA256:fp")

        let evaluator = HostKeyTrustEvaluator(
            knownHostStore: knownHostStore,
            fingerprintResolver: FixedFingerprintResolver(fingerprint: "SHA256:fp")
        )
        let viewModel = HostListViewModel(repository: repository, hostKeyTrustEvaluator: evaluator)

        // Editing a non-endpoint field (alias) must NOT remove the existing pin.
        var aliasDraft = ConnectionDraft(connection: connection)
        aliasDraft.alias = "Renamed Box"
        viewModel.save(aliasDraft)

        XCTAssertNotNil(
            try knownHostStore.knownHost(host: "old.example.com", port: 22),
            "editing a non-endpoint field must not remove the known-host pin"
        )

        // Editing the host must remove the pin for the OLD host:port.
        var hostDraft = ConnectionDraft(connection: connection)
        hostDraft.host = "new.example.com"
        viewModel.save(hostDraft)

        XCTAssertNil(
            try knownHostStore.knownHost(host: "old.example.com", port: 22),
            "editing the host must remove the stale pin for the old endpoint"
        )
    }
}
