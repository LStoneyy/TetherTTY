import Foundation
import Security

protocol CredentialStore {
    func savePassword(_ password: String, for connectionID: UUID) throws
    func hasPassword(for connectionID: UUID) -> Bool
    func deletePassword(for connectionID: UUID) throws
}

enum CredentialStoreError: Error, Equatable {
    case unhandledStatus(OSStatus)
}

final class KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = "dev.tethertty.credentials") {
        self.service = service
    }

    func savePassword(_ password: String, for connectionID: UUID) throws {
        let data = Data(password.utf8)
        let query = baseQuery(for: connectionID)

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.unhandledStatus(status)
        }
    }

    func hasPassword(for connectionID: UUID) -> Bool {
        var query = baseQuery(for: connectionID)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func deletePassword(for connectionID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
    }
}

final class InMemoryCredentialStore: CredentialStore {
    private var passwords: [UUID: String] = [:]

    func savePassword(_ password: String, for connectionID: UUID) throws {
        passwords[connectionID] = password
    }

    func hasPassword(for connectionID: UUID) -> Bool {
        passwords[connectionID] != nil
    }

    func deletePassword(for connectionID: UUID) throws {
        passwords[connectionID] = nil
    }
}
