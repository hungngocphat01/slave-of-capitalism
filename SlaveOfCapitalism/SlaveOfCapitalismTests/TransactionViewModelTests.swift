import XCTest
@testable import SlaveOfCapitalism

@MainActor
final class TransactionViewModelTests: XCTestCase {
    func testLoadRequestsSelectedMonthAndStoresTransactions() async {
        let client = TransactionAPIStub()
        client.listTransactionsHandler = { month in
            XCTAssertEqual(month, "2026-03-01")
            return [
                Self.makeTransaction(id: 1, date: "2026-03-05", description: "Groceries"),
                Self.makeTransaction(id: 2, date: "2026-03-06", description: "Salary", direction: .inflow, classification: .income)
            ]
        }

        let viewModel = TransactionViewModel(apiClient: client, selectedYear: 2026, selectedMonth: 3)
        await viewModel.load()

        XCTAssertEqual(client.listTransactionsMonths, ["2026-03-01"])
        XCTAssertEqual(viewModel.transactions.map(\.id), [1, 2])
        XCTAssertTrue(viewModel.selectedIds.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadAfterMonthChangeUsesUpdatedMonthAndReconcilesSelection() async {
        let client = TransactionAPIStub()
        client.listTransactionsHandler = { month in
            switch month {
            case "2026-03-01":
                return [
                    Self.makeTransaction(id: 1, date: "2026-03-05", description: "Groceries"),
                    Self.makeTransaction(id: 2, date: "2026-03-06", description: "Coffee")
                ]
            case "2026-04-01":
                return [
                    Self.makeTransaction(id: 2, date: "2026-04-01", description: "Coffee"),
                    Self.makeTransaction(id: 3, date: "2026-04-02", description: "Rent")
                ]
            default:
                return []
            }
        }

        let viewModel = TransactionViewModel(apiClient: client, selectedYear: 2026, selectedMonth: 3)
        await viewModel.load()
        viewModel.selectedIds = [1, 2]

        viewModel.selectedMonth = 4
        await viewModel.load()

        XCTAssertEqual(client.listTransactionsMonths, ["2026-03-01", "2026-04-01"])
        XCTAssertEqual(viewModel.transactions.map(\.id), [2, 3])
        XCTAssertEqual(viewModel.selectedIds, [2])
    }

    func testDeleteSelectedDeletesIdsClearsSelectionAndReloads() async {
        let client = TransactionAPIStub()
        client.listTransactionsHandler = { month in
            XCTAssertEqual(month, "2026-03-01")
            if client.listTransactionsMonths.count == 1 {
                return [
                    Self.makeTransaction(id: 1, date: "2026-03-05", description: "Groceries"),
                    Self.makeTransaction(id: 2, date: "2026-03-06", description: "Coffee")
                ]
            }
            return [
                Self.makeTransaction(id: 2, date: "2026-03-06", description: "Coffee")
            ]
        }

        let viewModel = TransactionViewModel(apiClient: client, selectedYear: 2026, selectedMonth: 3)
        await viewModel.load()
        viewModel.selectedIds = [1]

        await viewModel.deleteSelected()

        XCTAssertEqual(client.deletedTransactionIds, [[1]])
        XCTAssertEqual(client.listTransactionsMonths, ["2026-03-01", "2026-03-01"])
        XCTAssertEqual(viewModel.transactions.map(\.id), [2])
        XCTAssertTrue(viewModel.selectedIds.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    func testIgnoreAndUnignoreSelectedReloadAndClearSelection() async {
        let client = TransactionAPIStub()
        client.listTransactionsHandler = { _ in
            [
                Self.makeTransaction(id: 1, date: "2026-03-05", description: "Groceries"),
                Self.makeTransaction(id: 2, date: "2026-03-06", description: "Coffee", isIgnored: true)
            ]
        }

        let viewModel = TransactionViewModel(apiClient: client, selectedYear: 2026, selectedMonth: 3)
        await viewModel.load()

        viewModel.selectedIds = [1]
        await viewModel.ignoreSelected()

        XCTAssertEqual(client.ignoredTransactionIds, [[1]])
        XCTAssertTrue(viewModel.selectedIds.isEmpty)

        viewModel.selectedIds = [2]
        await viewModel.unignoreSelected()

        XCTAssertEqual(client.unignoredTransactionIds, [[2]])
        XCTAssertTrue(viewModel.selectedIds.isEmpty)
        XCTAssertEqual(client.listTransactionsMonths, ["2026-03-01", "2026-03-01", "2026-03-01"])
    }

    func testLoadStoresAPIErrors() async {
        let client = TransactionAPIStub()
        client.listTransactionsError = APIError.serverError("Transaction load failed")

        let viewModel = TransactionViewModel(apiClient: client, selectedYear: 2026, selectedMonth: 3)
        await viewModel.load()

        XCTAssertTrue(viewModel.transactions.isEmpty)

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Transaction load failed")
        XCTAssertFalse(viewModel.isLoading)
    }

    private static func makeTransaction(
        id: Int,
        date: String,
        description: String,
        walletId: Int = 1,
        direction: TransactionDirection = .outflow,
        classification: TransactionClassification = .expense,
        amount: Decimal = 120,
        isIgnored: Bool = false,
        linkedEntry: LinkedEntryResponse? = nil
    ) -> TransactionWithDetails {
        TransactionWithDetails(
            id: id,
            date: date,
            time: nil,
            walletId: walletId,
            direction: direction,
            amount: amount,
            classification: classification,
            description: description,
            categoryId: nil,
            subcategoryId: nil,
            pairedTransactionId: nil,
            isIgnored: isIgnored,
            isCalibration: false,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z",
            walletName: "Cash",
            walletType: WalletType.normal.rawValue,
            categoryName: nil,
            subcategoryName: nil,
            hasLinkedEntry: linkedEntry != nil,
            isLinkedToEntry: false,
            linkedEntry: linkedEntry
        )
    }
}

private final class TransactionAPIStub: APIClientProtocol {
    var listTransactionsHandler: ((String?) throws -> [TransactionWithDetails])?
    var listTransactionsError: Error?
    var listTransactionsMonths: [String?] = []
    var deletedTransactionIds: [[Int]] = []
    var ignoredTransactionIds: [[Int]] = []
    var unignoredTransactionIds: [[Int]] = []

    func listWallets() async throws -> [WalletWithBalance] { [] }
    func getWallet(id: Int) async throws -> WalletWithBalance { fatalError("Unused") }
    func createWallet(_ body: WalletCreate) async throws -> WalletResponse { fatalError("Unused") }
    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse { fatalError("Unused") }
    func deleteWallet(id: Int) async throws { fatalError("Unused") }
    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse { fatalError("Unused") }
    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse { fatalError("Unused") }
    func getAudits() async throws -> [BalanceAuditResponse] { fatalError("Unused") }
    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse { fatalError("Unused") }

    func listTransactions(
        walletId: Int?,
        categoryId: Int?,
        month: String?,
        direction: TransactionDirection?,
        classification: TransactionClassification?
    ) async throws -> [TransactionWithDetails] {
        listTransactionsMonths.append(month)
        if let listTransactionsError {
            throw listTransactionsError
        }
        return try listTransactionsHandler?(month) ?? []
    }

    func getTransaction(id: Int) async throws -> TransactionWithDetails { fatalError("Unused") }
    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse { fatalError("Unused") }
    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse { fatalError("Unused") }
    func deleteTransaction(id: Int) async throws { fatalError("Unused") }
    func deleteTransactions(ids: [Int]) async throws { deletedTransactionIds.append(ids) }
    func ignoreTransactions(ids: [Int]) async throws { ignoredTransactionIds.append(ids) }
    func unignoreTransactions(ids: [Int]) async throws { unignoredTransactionIds.append(ids) }
    func reclassifyTransaction(id: Int, _ body: ReclassifyRequest) async throws -> TransactionResponse { fatalError("Unused") }
    func markAsSplit(id: Int, _ body: MarkAsSplitRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func markAsLoan(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func markAsDebt(id: Int, _ body: MarkAsDebtRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func markAsInstallment(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func unclassifyTransaction(id: Int) async throws { fatalError("Unused") }
    func unlinkTransaction(id: Int) async throws { fatalError("Unused") }
    func linkToEntry(_ body: BulkLinkRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func mergeTransactions(_ body: TransactionMergeRequest) async throws -> TransactionResponse { fatalError("Unused") }
    func resolveCalibration(id: Int, _ body: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse { fatalError("Unused") }
    func bulkImport(_ body: BulkImportRequest) async throws -> BulkImportResponse { fatalError("Unused") }
    func monthlySummary(month: String) async throws -> MonthlySummaryDict { fatalError("Unused") }

    func listCategories() async throws -> [CategoryWithSubcategories] { [] }
    func createCategory(_ body: CategoryCreate) async throws -> CategoryResponse { fatalError("Unused") }
    func updateCategory(id: Int, _ body: CategoryUpdate) async throws -> CategoryResponse { fatalError("Unused") }
    func deleteCategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws { fatalError("Unused") }
    func createSubcategory(categoryId: Int, _ body: SubcategoryCreate) async throws -> SubcategoryResponse { fatalError("Unused") }
    func updateSubcategory(id: Int, _ body: SubcategoryUpdate) async throws -> SubcategoryResponse { fatalError("Unused") }
    func deleteSubcategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws { fatalError("Unused") }

    func listLinkedEntries(linkType: LinkType?, status: LinkStatus?) async throws -> [LinkedEntryWithDetails] { fatalError("Unused") }
    func pendingEntries() async throws -> [LinkedEntryWithDetails] { fatalError("Unused") }
    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails { fatalError("Unused") }
    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails { fatalError("Unused") }
    func createLinkedEntry(_ body: LinkedEntryCreate) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func updateLinkedEntry(id: Int, _ body: LinkedEntryUpdate) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func deleteLinkedEntry(id: Int) async throws { fatalError("Unused") }
    func linkTransaction(entryId: Int, _ body: LinkTransactionRequest) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse { fatalError("Unused") }
    func summaryOwed() async throws -> OwedSummary { fatalError("Unused") }
    func summaryDebt() async throws -> DebtSummary { fatalError("Unused") }

    func listBudgets(year: Int?, month: Int?, categoryId: Int?) async throws -> [BudgetWithCategory] { fatalError("Unused") }
    func createBudget(_ body: BudgetCreate) async throws -> BudgetResponse { fatalError("Unused") }
    func updateBudget(id: Int, _ body: BudgetUpdate) async throws -> BudgetResponse { fatalError("Unused") }
    func deleteBudget(id: Int) async throws { fatalError("Unused") }
    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String?) async throws -> MonthlySummaryResponse { fatalError("Unused") }
    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse { fatalError("Unused") }

    func healthCheck() async throws -> Bool { true }
}
