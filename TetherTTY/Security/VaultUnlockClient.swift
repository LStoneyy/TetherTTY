import Foundation
import LocalAuthentication

protocol VaultUnlockClient {
    func unlock(reason: String) async -> VaultUnlockResult
}

enum VaultUnlockResult: Equatable {
    case unlocked
    case unavailable(String)
    case denied(String)
}

struct LocalAuthenticationVaultUnlockClient: VaultUnlockClient {
    func unlock(reason: String) async -> VaultUnlockResult {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? "Device authentication is unavailable.")
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .unlocked : .denied("Authentication was not completed.")
        } catch {
            return .denied(error.localizedDescription)
        }
    }
}

struct StubVaultUnlockClient: VaultUnlockClient {
    let result: VaultUnlockResult

    func unlock(reason: String) async -> VaultUnlockResult {
        result
    }
}
