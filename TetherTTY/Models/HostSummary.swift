import Foundation

struct HostSummary: Identifiable, Equatable {
    let id: UUID
    var alias: String
    var address: String
    var status: HostStatus
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        alias: String,
        address: String,
        status: HostStatus = .unknown,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.alias = alias
        self.address = address
        self.status = status
        self.isFavorite = isFavorite
    }
}

enum HostStatus: String, Equatable {
    case unknown = "Unknown"
    case reachable = "Reachable"
    case warning = "Needs Review"
    case failed = "Failed"
}
