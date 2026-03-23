import XCTest
@testable import SlaveOfCapitalism

private struct MonthlySummaryRequest: Equatable {
    let year: Int
    let month: Int
    let periodBoundaries: String?
}

private struct DailySummaryRequest: Equatable {
    let year: Int
    let month: Int
}

@MainActor
final class SummaryViewModelTests: XCTestCase {
    func testLoadFetchesMonthlyAndDailySummaries() async {
        let client = SummaryAPIStub()
        client.monthlyResult = makeMonthlySummary(year: 2026, month: 3, budget: 1200, actual: 420)
        client.dailyResult = makeDailySummary(year: 2026, month: 3, daysInMonth: 31)

        let viewModel = SummaryViewModel(apiClient: client, year: 2026, month: 3)
        await viewModel.load()

        XCTAssertEqual(
            client.monthlyRequests,
            [MonthlySummaryRequest(year: 2026, month: 3, periodBoundaries: nil)]
        )
        XCTAssertEqual(
            client.dailyRequests,
            [DailySummaryRequest(year: 2026, month: 3)]
        )
        XCTAssertEqual(viewModel.monthlySummary?.year, 2026)
        XCTAssertEqual(viewModel.monthlySummary?.month, 3)
        XCTAssertEqual(viewModel.dailySummary?.daysInMonth, 31)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadAfterMonthChangeUsesUpdatedMonth() async {
        let client = SummaryAPIStub()
        client.monthlyResult = makeMonthlySummary(year: 2026, month: 3, budget: 1200, actual: 420)
        client.dailyResult = makeDailySummary(year: 2026, month: 3, daysInMonth: 31)

        let viewModel = SummaryViewModel(apiClient: client, year: 2026, month: 3)
        await viewModel.load()

        client.monthlyResult = makeMonthlySummary(year: 2026, month: 4, budget: 800, actual: 120)
        client.dailyResult = makeDailySummary(year: 2026, month: 4, daysInMonth: 30)
        viewModel.month = 4

        await viewModel.load()

        XCTAssertEqual(
            client.monthlyRequests,
            [
                MonthlySummaryRequest(year: 2026, month: 3, periodBoundaries: nil),
                MonthlySummaryRequest(year: 2026, month: 4, periodBoundaries: nil)
            ]
        )
        XCTAssertEqual(
            client.dailyRequests,
            [
                DailySummaryRequest(year: 2026, month: 3),
                DailySummaryRequest(year: 2026, month: 4)
            ]
        )
        XCTAssertEqual(viewModel.monthlySummary?.month, 4)
        XCTAssertEqual(viewModel.dailySummary?.month, 4)
    }

    func testThresholdClassifiesBudgetUsage() {
        let client = SummaryAPIStub()
        let viewModel = SummaryViewModel(apiClient: client, year: 2026, month: 3)

        XCTAssertEqual(viewModel.threshold(for: 0), .neutral)
        XCTAssertEqual(viewModel.threshold(for: 55), .safe)
        XCTAssertEqual(viewModel.threshold(for: 90), .warning)
        XCTAssertEqual(viewModel.threshold(for: 109.9), .warning)
        XCTAssertEqual(viewModel.threshold(for: 110), .warning)
        XCTAssertEqual(viewModel.threshold(for: 110.1), .danger)
    }

    func testLoadStoresAPIErrors() async {
        let client = SummaryAPIStub()
        client.errorToThrow = APIError.serverError("Summary load failed")

        let viewModel = SummaryViewModel(apiClient: client, year: 2026, month: 3)
        await viewModel.load()

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Summary load failed")
        XCTAssertNil(viewModel.monthlySummary)
        XCTAssertNil(viewModel.dailySummary)
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeMonthlySummary(year: Int, month: Int, budget: Decimal, actual: Decimal) -> MonthlySummaryResponse {
        MonthlySummaryResponse(
            year: year,
            month: month,
            categories: [
                CategorySummary(
                    categoryId: 1,
                    categoryName: "Food",
                    emoji: "🍜",
                    color: "#34C759",
                    budget: 500,
                    actual: 200,
                    percentage: 40,
                    periods: [80, 70, 50, 0],
                    subcategories: []
                )
            ],
            totalBudget: budget,
            totalActual: actual,
            periodBoundaries: [7, 14, 21, 31]
        )
    }

    private func makeDailySummary(year: Int, month: Int, daysInMonth: Int) -> DailySummaryResponse {
        DailySummaryResponse(
            year: year,
            month: month,
            daysInMonth: daysInMonth,
            categories: [
                DailyCategoryData(
                    categoryId: 1,
                    categoryName: "Food",
                    emoji: "🍜",
                    color: "#34C759",
                    budget: 500,
                    dailyAmounts: Array(repeating: 10, count: daysInMonth),
                    subcategories: []
                )
            ]
        )
    }
}

private final class SummaryAPIStub: APIClientProtocol {
    var errorToThrow: Error?
    var monthlyResult: MonthlySummaryResponse?
    var dailyResult: DailySummaryResponse?
    var monthlyRequests: [MonthlySummaryRequest] = []
    var dailyRequests: [DailySummaryRequest] = []

    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String?) async throws -> MonthlySummaryResponse {
        monthlyRequests.append(
            MonthlySummaryRequest(
                year: year,
                month: month,
                periodBoundaries: periodBoundaries
            )
        )
        if let errorToThrow { throw errorToThrow }
        return monthlyResult!
    }

    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse {
        dailyRequests.append(DailySummaryRequest(year: year, month: month))
        if let errorToThrow { throw errorToThrow }
        return dailyResult!
    }

    func healthCheck() async throws -> Bool { true }

    func listWallets() async throws -> [WalletWithBalance] { fatalError("Unused") }
    func getWallet(id: Int) async throws -> WalletWithBalance { fatalError("Unused") }
    func createWallet(_ body: WalletCreate) async throws -> WalletResponse { fatalError("Unused") }
    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse { fatalError("Unused") }
    func deleteWallet(id: Int) async throws { fatalError("Unused") }
    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse { fatalError("Unused") }
    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse { fatalError("Unused") }
    func getAudits() async throws -> [BalanceAuditResponse] { fatalError("Unused") }
    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse { fatalError("Unused") }
    func listTransactions(walletId: Int?, categoryId: Int?, month: String?, direction: TransactionDirection?, classification: TransactionClassification?) async throws -> [TransactionWithDetails] { fatalError("Unused") }
    func getTransaction(id: Int) async throws -> TransactionWithDetails { fatalError("Unused") }
    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse { fatalError("Unused") }
    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse { fatalError("Unused") }
    func deleteTransaction(id: Int) async throws { fatalError("Unused") }
    func deleteTransactions(ids: [Int]) async throws { fatalError("Unused") }
    func ignoreTransactions(ids: [Int]) async throws { fatalError("Unused") }
    func unignoreTransactions(ids: [Int]) async throws { fatalError("Unused") }
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
    func listCategories() async throws -> [CategoryWithSubcategories] { fatalError("Unused") }
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
}
