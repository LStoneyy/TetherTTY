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
