import XCTest
@testable import SlaveOfCapitalism

@MainActor
final class PendingViewModelTests: XCTestCase {
    func testLoadGroupsEntriesAndComputesTotals() async {
        let client = MockAPIClient()
        client.pendingEntriesResult = [
            makeEntry(id: 1, linkType: .splitPayment, pendingAmount: 120),
            makeEntry(id: 2, linkType: .loan, pendingAmount: 80),
            makeEntry(id: 3, linkType: .debt, pendingAmount: 60),
            makeEntry(id: 4, linkType: .installment, pendingAmount: 40)
        ]

        let viewModel = PendingViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertEqual(client.callLog, ["pendingEntries"])
        XCTAssertEqual(viewModel.owedEntries.map(\.id), [1, 2])
        XCTAssertEqual(viewModel.debtEntries.map(\.id), [3])
        XCTAssertEqual(viewModel.installmentEntries.map(\.id), [4])
        XCTAssertEqual(viewModel.totalOwed, Decimal(200))
        XCTAssertEqual(viewModel.totalDebt, Decimal(60))
        XCTAssertEqual(viewModel.totalInstallments, Decimal(40))
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadLinkableTransactionsFiltersCandidatesByEntryType() async {
        let client = MockAPIClient()
        client.transactionsResult = [
            makeTransaction(
                id: 1,
                date: "2026-03-01",
                direction: .inflow,
                classification: .income
            ),
            makeTransaction(
                id: 2,
                date: "2026-03-02",
                direction: .inflow,
                classification: .debtCollection
            ),
            makeTransaction(
                id: 3,
                date: "2026-03-03",
                direction: .inflow,
                classification: .expense
            ),
            makeTransaction(
                id: 4,
                date: "2026-03-04",
                direction: .outflow,
                classification: .expense
            ),
            makeTransaction(
                id: 5,
                date: "2026-03-05",
                direction: .inflow,
                classification: .income,
                isLinkedToEntry: true
            )
        ]

        let viewModel = PendingViewModel(apiClient: client)
        await viewModel.loadLinkableTransactions(for: makeEntry(id: 11, linkType: .loan, pendingAmount: 500))

        XCTAssertEqual(client.callLog, ["listTransactions"])
        XCTAssertEqual(viewModel.linkableTransactions(for: 11).map(\.id), [2, 1])
        XCTAssertNil(viewModel.error)
    }

    func testLinkTransactionReloadsPendingEntries() async {
        let client = MockAPIClient()
        client.pendingEntriesResult = [
            makeEntry(id: 21, linkType: .debt, pendingAmount: 300)
        ]
        client.linkTransactionResult = makeLinkedEntryResponse(id: 21, linkType: .debt, pendingAmount: 120)

        let viewModel = PendingViewModel(apiClient: client)
        await viewModel.load()
        client.pendingEntriesResult = [
            makeEntry(id: 21, linkType: .debt, pendingAmount: 120, status: .partial)
        ]

        let didLink = await viewModel.linkTransaction(entryId: 21, transactionId: 101)

        XCTAssertTrue(didLink)
        XCTAssertEqual(client.callLog, ["pendingEntries", "linkTransaction", "pendingEntries"])
        XCTAssertEqual(viewModel.entries.first?.pendingAmount, Decimal(120))
        XCTAssertEqual(viewModel.entries.first?.status, .partial)
        XCTAssertFalse(viewModel.isLinking)
        XCTAssertNil(viewModel.error)
    }

    private func makeEntry(
        id: Int,
        linkType: LinkType,
        pendingAmount: Decimal,
        status: LinkStatus = .pending
    ) -> LinkedEntryWithDetails {
        LinkedEntryWithDetails(
            id: id,
            linkType: linkType,
            primaryTransactionId: id * 10,
            counterpartyName: "Entry \(id)",
            totalAmount: pendingAmount + 100,
            userAmount: nil,
            pendingAmount: pendingAmount,
            status: status,
            notes: nil,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z",
            linkedTransactions: [],
            primaryTransactionDescription: "Sample",
            primaryTransactionDate: "2026-03-01",
            settledAmount: 0
        )
    }

    private func makeTransaction(
        id: Int,
        date: String,
        direction: TransactionDirection,
        classification: TransactionClassification,
        isLinkedToEntry: Bool = false
    ) -> TransactionWithDetails {
        TransactionWithDetails(
            id: id,
            date: date,
            time: nil,
            walletId: 1,
            direction: direction,
            amount: Decimal(100),
            classification: classification,
            description: "Tx \(id)",
            categoryId: nil,
            subcategoryId: nil,
            pairedTransactionId: nil,
            isIgnored: false,
            isCalibration: false,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z",
            walletName: "Cash",
            walletType: WalletType.normal.rawValue,
            categoryName: nil,
            subcategoryName: nil,
            hasLinkedEntry: isLinkedToEntry,
            isLinkedToEntry: isLinkedToEntry,
            linkedEntry: nil
        )
    }

    private func makeLinkedEntryResponse(
        id: Int,
        linkType: LinkType,
        pendingAmount: Decimal
    ) -> LinkedEntryResponse {
        LinkedEntryResponse(
            id: id,
            linkType: linkType,
            primaryTransactionId: id * 10,
            counterpartyName: "Entry \(id)",
            totalAmount: pendingAmount + 100,
            userAmount: nil,
            pendingAmount: pendingAmount,
            status: .partial,
            notes: nil,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z",
            linkedTransactions: []
        )
    }
}
