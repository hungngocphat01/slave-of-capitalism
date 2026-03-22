import XCTest
@testable import SlaveOfCapitalism

@MainActor
final class WalletViewModelTests: XCTestCase {
    func testLoadFetchesWalletsOnAppear() async {
        let client = MockAPIClient()
        client.walletsResult = [
            makeWallet(id: 1, name: "Cash", type: .normal, balance: 1200),
            makeWallet(id: 2, name: "Visa", type: .credit, balance: 400, creditLimit: 2000, availableCredit: 1600)
        ]

        let viewModel = WalletViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertEqual(client.callLog, ["listWallets"])
        XCTAssertEqual(viewModel.wallets.map(\.id), [1, 2])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadHandlesEmptyState() async {
        let client = MockAPIClient()
        client.walletsResult = []

        let viewModel = WalletViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertTrue(viewModel.wallets.isEmpty)
        XCTAssertEqual(viewModel.totalAssets, 0)
        XCTAssertEqual(viewModel.totalCreditUsed, 0)
        XCTAssertEqual(viewModel.totalAvailableCredit, 0)
        XCTAssertEqual(viewModel.netPosition, 0)
        XCTAssertNil(viewModel.error)
    }

    func testLoadStoresAPIErrors() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Wallet load failed")

        let viewModel = WalletViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertTrue(viewModel.wallets.isEmpty)

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Wallet load failed")
    }

    func testSummaryCalculationsTrackAvailableCreditAndNetPosition() async {
        let client = MockAPIClient()
        client.walletsResult = [
            makeWallet(id: 1, name: "Cash", type: .normal, balance: 1200),
            makeWallet(id: 2, name: "Bank", type: .normal, balance: 300),
            makeWallet(id: 3, name: "Visa", type: .credit, balance: 400, creditLimit: 2000, availableCredit: 1600),
            makeWallet(id: 4, name: "Mastercard", type: .credit, balance: 250, creditLimit: 1000, availableCredit: 750)
        ]

        let viewModel = WalletViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertEqual(viewModel.totalAssets, 1500)
        XCTAssertEqual(viewModel.totalCreditUsed, 650)
        XCTAssertEqual(viewModel.totalAvailableCredit, 3850)
        XCTAssertEqual(viewModel.netPosition, 850)
    }

    func testDeleteWalletReloadsWalletsOnSuccess() async {
        let client = MockAPIClient()
        client.walletsResult = [
            makeWallet(id: 2, name: "Visa", type: .credit, balance: 400, creditLimit: 2000, availableCredit: 1600)
        ]

        let viewModel = WalletViewModel(apiClient: client)
        let wasDeleted = await viewModel.deleteWallet(id: 1)

        XCTAssertTrue(wasDeleted)
        XCTAssertEqual(client.callLog, ["deleteWallet", "listWallets"])
        XCTAssertEqual(viewModel.wallets.map(\.id), [2])
        XCTAssertNil(viewModel.error)
    }

    func testDeleteWalletStoresErrorAndSkipsReloadOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Delete failed")

        let viewModel = WalletViewModel(apiClient: client)
        let wasDeleted = await viewModel.deleteWallet(id: 1)

        XCTAssertFalse(wasDeleted)
        XCTAssertEqual(client.callLog, ["deleteWallet"])
        XCTAssertTrue(viewModel.wallets.isEmpty)

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Delete failed")
    }

    private func makeWallet(
        id: Int,
        name: String,
        type: WalletType,
        balance: Decimal,
        creditLimit: Decimal = 0,
        availableCredit: Decimal? = nil,
        emoji: String? = nil
    ) -> WalletWithBalance {
        WalletWithBalance(
            id: id,
            name: name,
            walletType: type,
            creditLimit: creditLimit,
            emoji: emoji,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z",
            currentBalance: balance,
            availableCredit: availableCredit
        )
    }
}
