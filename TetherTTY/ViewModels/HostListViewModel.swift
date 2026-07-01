import Foundation

@MainActor
final class HostListViewModel: ObservableObject {
    @Published private(set) var connections: [Connection] = []
    @Published var errorMessage: String?

    private let repository: ConnectionRepository

    init(repository: ConnectionRepository = LocalConnectionRepository()) {
        self.repository = repository
        reload()
    }

    func reload() {
        do {
            connections = try repository.loadConnections()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load saved tethers."
        }
    }

    func save(_ draft: ConnectionDraft) {
        do {
            try repository.saveConnection(draft.connection, password: draft.passwordForSaving)
            reload()
        } catch {
            errorMessage = "Could not save this tether."
        }
    }

    func delete(_ connection: Connection) {
        do {
            try repository.deleteConnection(id: connection.id)
            reload()
        } catch {
            errorMessage = "Could not delete this tether."
        }
    }

    func toggleFavorite(_ connection: Connection) {
        do {
            try repository.toggleFavorite(id: connection.id)
            reload()
        } catch {
            errorMessage = "Could not update favorite state."
        }
    }

    func hasPassword(for connection: Connection) -> Bool {
        repository.hasPassword(for: connection.id)
    }
}

struct ConnectionDraft: Equatable {
    var id: UUID
    var alias: String
    var host: String
    var port: String
    var username: String
    var password: String
    var isFavorite: Bool
    var createdAt: Date

    init(connection: Connection? = nil) {
        let connection = connection ?? Connection(alias: "", host: "", username: "")
        id = connection.id
        alias = connection.alias
        host = connection.host
        port = String(connection.port)
        username = connection.username
        password = ""
        isFavorite = connection.isFavorite
        createdAt = connection.createdAt
    }

    var isValid: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            parsedPort != nil
    }

    var connection: Connection {
        Connection(
            id: id,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: parsedPort ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            isFavorite: isFavorite,
            createdAt: createdAt
        )
    }

    var passwordForSaving: String? {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : password
    }

    private var parsedPort: Int? {
        guard let value = Int(port), (1...65535).contains(value) else {
            return nil
        }

        return value
    }
}
