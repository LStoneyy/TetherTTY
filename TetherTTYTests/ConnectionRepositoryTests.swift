import Foundation
import XCTest
@testable import TetherTTY

final class ConnectionRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var credentialStore: InMemoryCredentialStore!
    private var repository: LocalConnectionRepository!

    override func setUp() {
        super.setUp()
        suiteName = "ConnectionRepositoryTests-\(UUID().uuidString)"
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

    func testSavingConnectionPersistsMetadataAndStoresPasswordSeparately() throws {
        let connection = Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas")

        try repository.saveConnection(connection, password: "correct horse battery staple")

        let loaded = try repository.loadConnections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, connection.id)
        XCTAssertEqual(loaded.first?.alias, "Laptop")
        XCTAssertEqual(loaded.first?.displayAddress, "lukas@192.0.2.42:22")
        XCTAssertTrue(repository.hasPassword(for: connection.id))
        XCTAssertEqual(try repository.password(for: connection.id), "correct horse battery staple")
        XCTAssertFalse(storedConnectionPayload().contains("correct horse battery staple"))
    }

    func testEditingConnectionDoesNotRequireReplacingPassword() throws {
        var connection = Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        connection.alias = "Main Laptop"
        try repository.saveConnection(connection, password: nil)

        XCTAssertEqual(try repository.loadConnections().first?.alias, "Main Laptop")
        XCTAssertTrue(repository.hasPassword(for: connection.id))
    }

    func testDeleteRemovesConnectionAndCredential() throws {
        let connection = Connection(alias: "Laptop", host: "192.0.2.42", username: "lukas")
        try repository.saveConnection(connection, password: "secret")

        try repository.deleteConnection(id: connection.id)

        XCTAssertTrue(try repository.loadConnections().isEmpty)
        XCTAssertFalse(repository.hasPassword(for: connection.id))
    }

    func testFavoritesSortBeforeOtherConnections() throws {
        let regular = Connection(alias: "Regular", host: "198.51.100.1", username: "lukas")
        let favorite = Connection(alias: "Favorite", host: "198.51.100.2", username: "lukas", isFavorite: true)

        try repository.saveConnection(regular, password: "one")
        try repository.saveConnection(favorite, password: "two")

        XCTAssertEqual(try repository.loadConnections().map(\.alias), ["Favorite", "Regular"])
    }

    private func storedConnectionPayload() -> String {
        let data = defaults.data(forKey: "connections.v1") ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
