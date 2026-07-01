import Foundation

protocol ConnectionRepository {
    func loadConnections() throws -> [Connection]
    func saveConnection(_ connection: Connection, password: String?) throws
    func deleteConnection(id: UUID) throws
    func toggleFavorite(id: UUID) throws
    func hasPassword(for connectionID: UUID) -> Bool
}

enum ConnectionRepositoryError: Error, Equatable {
    case connectionNotFound
}

final class LocalConnectionRepository: ConnectionRepository {
    private let defaults: UserDefaults
    private let credentialStore: CredentialStore
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        credentialStore: CredentialStore = KeychainCredentialStore(),
        storageKey: String = "connections.v1"
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.storageKey = storageKey
    }

    func loadConnections() throws -> [Connection] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return try decoder.decode([Connection].self, from: data)
            .sorted(by: sortConnections)
    }

    func saveConnection(_ connection: Connection, password: String?) throws {
        var connections = try loadConnections()
        var saved = connection
        saved.updatedAt = Date()

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            saved.createdAt = connections[index].createdAt
            connections[index] = saved
        } else {
            connections.append(saved)
        }

        try persist(connections)

        if let password, !password.isEmpty {
            try credentialStore.savePassword(password, for: connection.id)
        }
    }

    func deleteConnection(id: UUID) throws {
        let remaining = try loadConnections().filter { $0.id != id }
        try persist(remaining)
        try credentialStore.deletePassword(for: id)
    }

    func toggleFavorite(id: UUID) throws {
        var connections = try loadConnections()
        guard let index = connections.firstIndex(where: { $0.id == id }) else {
            throw ConnectionRepositoryError.connectionNotFound
        }

        connections[index].isFavorite.toggle()
        connections[index].updatedAt = Date()
        try persist(connections)
    }

    func hasPassword(for connectionID: UUID) -> Bool {
        credentialStore.hasPassword(for: connectionID)
    }

    private func persist(_ connections: [Connection]) throws {
        let data = try encoder.encode(connections.sorted(by: sortConnections))
        defaults.set(data, forKey: storageKey)
    }

    private func sortConnections(_ lhs: Connection, _ rhs: Connection) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }

        return lhs.updatedAt > rhs.updatedAt
    }
}
