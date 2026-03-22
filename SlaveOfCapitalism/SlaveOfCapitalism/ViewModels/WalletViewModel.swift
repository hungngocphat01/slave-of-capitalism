import Foundation
import Observation

@MainActor
@Observable
final class WalletViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var wallets: [WalletWithBalance] = []
    private(set) var isLoading = false
    var error: APIError?

    var totalAssets: Decimal {
        wallets
            .filter { $0.walletType == .normal }
            .reduce(0) { $0 + $1.currentBalance }
    }

    var totalCreditUsed: Decimal {
        wallets
            .filter { $0.walletType == .credit }
            .reduce(0) { $0 + $1.currentBalance }
    }

    var totalAvailableCredit: Decimal {
        let liquidAssets = wallets
            .filter { $0.walletType == .normal }
            .reduce(0) { $0 + $1.currentBalance }

        let remainingCredit = wallets
            .filter { $0.walletType == .credit }
            .reduce(0) { $0 + ($1.availableCredit ?? 0) }

        return liquidAssets + remainingCredit
    }

    var netPosition: Decimal {
        totalAssets - totalCreditUsed
    }

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            wallets = try await apiClient.listWallets()
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func deleteWallet(id: Int) async -> Bool {
        do {
            try await apiClient.deleteWallet(id: id)
            await load()
            return true
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }

        return false
    }
}
