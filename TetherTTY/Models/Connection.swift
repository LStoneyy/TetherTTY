import Foundation

struct Connection: Identifiable, Codable, Equatable {
    let id: UUID
    var alias: String
    var host: String
    var port: Int
    var username: String
    var isFavorite: Bool
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        alias: String,
        host: String,
        port: Int = 22,
        username: String,
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.alias = alias
        self.host = host
        self.port = port
        self.username = username
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayAddress: String {
        "\(username)@\(host):\(port)"
    }
}

/// Validation and normalization rules shared by everything that turns raw user input into a
/// `Connection` (currently `ConnectionDraft`). Kept independent of any storage/security type so
/// it can be reused without coupling the model layer to `KnownHostStore` or the repository.
enum ConnectionInputValidation {
    static let maxHostLength = 253
    static let maxUsernameLength = 256
    static let maxAliasLength = 100
    static let portRange = 1...65535

    /// Matches a leading `<scheme>://` prefix (e.g. `ssh://`, `HTTP://`), which must never be
    /// accepted as part of a bare host value.
    private static let schemePrefixRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9+.-]*://")
    }()

    /// True if `value` contains any Unicode control character (general categories Cc/Cf),
    /// which covers CR, LF, Tab and NUL among others.
    static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func hasSchemePrefix(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return schemePrefixRegex.firstMatch(in: value, range: range) != nil
    }

    /// `trimmedHost` must already be whitespace-trimmed by the caller.
    static func isValidHost(_ trimmedHost: String) -> Bool {
        !trimmedHost.isEmpty &&
            trimmedHost.count <= maxHostLength &&
            !containsControlCharacters(trimmedHost) &&
            !hasSchemePrefix(trimmedHost)
    }

    /// `trimmedUsername` must already be whitespace-trimmed by the caller.
    static func isValidUsername(_ trimmedUsername: String) -> Bool {
        !trimmedUsername.isEmpty &&
            trimmedUsername.count <= maxUsernameLength &&
            !containsControlCharacters(trimmedUsername)
    }

    /// `trimmedAlias` must already be whitespace-trimmed by the caller.
    static func isValidAlias(_ trimmedAlias: String) -> Bool {
        !trimmedAlias.isEmpty &&
            trimmedAlias.count <= maxAliasLength &&
            !containsControlCharacters(trimmedAlias)
    }

    static func isValidPort(_ port: Int) -> Bool {
        portRange.contains(port)
    }

    /// Produces the canonical host string used consistently for both the SSH connect and the
    /// known-host pin lookup: DNS-style hostnames are lowercased and a single optional trailing
    /// dot is stripped (`Example.COM.` -> `example.com`). IPv4/IPv6 literals are left structurally
    /// untouched (their dots/colons/brackets are never rewritten); lowercasing an IPv6 literal's
    /// hex digits is safe and doesn't change its meaning.
    static func normalizeHost(_ trimmedHost: String) -> String {
        var host = trimmedHost.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }
}
