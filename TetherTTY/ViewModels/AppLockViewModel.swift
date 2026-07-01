import Foundation

@MainActor
final class AppLockViewModel: ObservableObject {
    @Published private(set) var lockState: AppLockState = .locked
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let unlockClient: VaultUnlockClient

    init(unlockClient: VaultUnlockClient = LocalAuthenticationVaultUnlockClient()) {
        self.unlockClient = unlockClient
    }

    func unlock() async {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        errorMessage = nil

        let result = await unlockClient.unlock(reason: "Unlock TetherTTY to access saved SSH tethers.")
        isAuthenticating = false

        switch result {
        case .unlocked:
            lockState = .unlocked
        case .unavailable(let message), .denied(let message):
            lockState = .locked
            errorMessage = message
        }
    }
}
