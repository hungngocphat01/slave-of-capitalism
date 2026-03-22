import Foundation
import Observation

@Observable
final class WalletStore {

    private(set) var wallets: [WalletWithBalance] = []
    private(set) var isLoading = false

    private var apiClient: APIClient?

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let apiClient else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            wallets = try await apiClient.listWallets()
        } catch {
            print("Failed to refresh wallets: \(error)")
        }
    }

    func wallet(for id: Int) -> WalletWithBalance? {
        wallets.first { $0.id == id }
    }
}
