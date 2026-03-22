import Foundation
import Observation

@MainActor
@Observable
final class WalletStore {

    private(set) var wallets: [WalletWithBalance] = []
    private(set) var isLoading = false
    private(set) var lastErrorMessage: String?

    private var apiClient: (any APIClientProtocol)?

    func configure(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let apiClient else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            wallets = try await apiClient.listWallets()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            print("Failed to refresh wallets: \(error)")
        }
    }

    func wallet(for id: Int) -> WalletWithBalance? {
        wallets.first { $0.id == id }
    }
}
