import Foundation

protocol KnownHostStore {
    func knownHost(host: String, port: Int) throws -> KnownHost?
    func trustHost(host: String, port: Int, fingerprint: String) throws
}

final class LocalKnownHostStore: KnownHostStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, storageKey: String = "known-hosts.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func knownHost(host: String, port: Int) throws -> KnownHost? {
        try load()[KnownHost.key(host: host, port: port)]
    }

    func trustHost(host: String, port: Int, fingerprint: String) throws {
        var knownHosts = try load()
        let knownHost = KnownHost(host: host, port: port, fingerprint: fingerprint, firstSeenAt: Date())
        knownHosts[knownHost.key] = knownHost
        let data = try encoder.encode(knownHosts)
        defaults.set(data, forKey: storageKey)
    }

    private func load() throws -> [String: KnownHost] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return try decoder.decode([String: KnownHost].self, from: data)
    }
}

final class InMemoryKnownHostStore: KnownHostStore {
    private var knownHosts: [String: KnownHost] = [:]

    func knownHost(host: String, port: Int) throws -> KnownHost? {
        knownHosts[KnownHost.key(host: host, port: port)]
    }

    func trustHost(host: String, port: Int, fingerprint: String) throws {
        let knownHost = KnownHost(host: host, port: port, fingerprint: fingerprint, firstSeenAt: Date())
        knownHosts[knownHost.key] = knownHost
    }
}
