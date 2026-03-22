import Foundation
@testable import SlaveOfCapitalism

final class MockAPIClient: APIClientProtocol {
    var errorToThrow: Error?

    var lastCalledMethod: String?
    var callCount = 0

    // Wallets
    var walletsResult: [WalletWithBalance] = []
    var walletResult: WalletWithBalance?
    var createWalletResult: WalletResponse?
    var updateWalletResult: WalletResponse?
    var transferResult: WalletTransferResponse?
    var calibrateWalletResult: TransactionResponse?
    var auditsResult: [BalanceAuditResponse] = []
    var createAuditResult: BalanceAuditResponse?

    // Transactions
    var transactionsResult: [TransactionWithDetails] = []
    var transactionResult: TransactionWithDetails?
    var createTransactionResult: TransactionResponse?
    var updateTransactionResult: TransactionResponse?
    var reclassifyTransactionResult: TransactionResponse?
    var markAsSplitResult: LinkedEntryResponse?
    var markAsLoanResult: LinkedEntryResponse?
    var markAsDebtResult: LinkedEntryResponse?
    var markAsInstallmentResult: LinkedEntryResponse?
    var linkToEntryResult: LinkedEntryResponse?
    var mergeTransactionsResult: TransactionResponse?
    var resolveCalibrationResult: ResolveCalibrationResponse?
    var bulkImportResult: BulkImportResponse?
    var monthlySummaryResult: MonthlySummaryDict?

    // Categories
    var categoriesResult: [CategoryWithSubcategories] = []
    var categoryResult: CategoryResponse?
    var updateCategoryResult: CategoryResponse?
    var createSubcategoryResult: SubcategoryResponse?
    var updateSubcategoryResult: SubcategoryResponse?

    // Linked Entries
    var linkedEntriesResult: [LinkedEntryWithDetails] = []
    var pendingEntriesResult: [LinkedEntryWithDetails] = []
    var linkedEntryResult: LinkedEntryWithDetails?
    var linkedEntryByTransactionResult: LinkedEntryWithDetails?
    var createLinkedEntryResult: LinkedEntryResponse?
    var updateLinkedEntryResult: LinkedEntryResponse?
    var linkTransactionResult: LinkedEntryResponse?
    var unlinkTransactionFromEntryResult: LinkedEntryResponse?
    var owedResult: OwedSummary?
    var debtResult: DebtSummary?

    // Budgets
    var budgetsResult: [BudgetWithCategory] = []
    var budgetResult: BudgetResponse?
    var updateBudgetResult: BudgetResponse?
    var monthlyBudgetSummaryResult: MonthlySummaryResponse?
    var dailyBudgetSummaryResult: DailySummaryResponse?

    // Health
    var healthCheckResult = true

    private func trackCall(_ method: String) throws {
        lastCalledMethod = method
        callCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    private func configured<T>(_ value: T?) -> T {
        guard let value else {
            fatalError("Mock not configured")
        }
        return value
    }

    func healthCheck() async throws -> Bool {
        try trackCall("healthCheck")
        return healthCheckResult
    }

    // Wallets

    func listWallets() async throws -> [WalletWithBalance] {
        try trackCall("listWallets")
        return walletsResult
    }

    func getWallet(id: Int) async throws -> WalletWithBalance {
        try trackCall("getWallet")
        return configured(walletResult)
    }

    func createWallet(_ body: WalletCreate) async throws -> WalletResponse {
        try trackCall("createWallet")
        return configured(createWalletResult)
    }

    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse {
        try trackCall("updateWallet")
        return configured(updateWalletResult)
    }

    func deleteWallet(id: Int) async throws {
        try trackCall("deleteWallet")
    }

    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse {
        try trackCall("transfer")
        return configured(transferResult)
    }

    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse {
        try trackCall("calibrateWallet")
        return configured(calibrateWalletResult)
    }

    func getAudits() async throws -> [BalanceAuditResponse] {
        try trackCall("getAudits")
        return auditsResult
    }

    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse {
        try trackCall("createAudit")
        return configured(createAuditResult)
    }

    // Transactions

    func listTransactions(
        walletId: Int? = nil,
        categoryId: Int? = nil,
        month: String? = nil,
        direction: TransactionDirection? = nil,
        classification: TransactionClassification? = nil
    ) async throws -> [TransactionWithDetails] {
        try trackCall("listTransactions")
        return transactionsResult
    }

    func getTransaction(id: Int) async throws -> TransactionWithDetails {
        try trackCall("getTransaction")
        return configured(transactionResult)
    }

    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse {
        try trackCall("createTransaction")
        return configured(createTransactionResult)
    }

    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse {
        try trackCall("updateTransaction")
        return configured(updateTransactionResult)
    }

    func deleteTransaction(id: Int) async throws {
        try trackCall("deleteTransaction")
    }

    func deleteTransactions(ids: [Int]) async throws {
        try trackCall("deleteTransactions")
    }

    func ignoreTransactions(ids: [Int]) async throws {
        try trackCall("ignoreTransactions")
    }

    func unignoreTransactions(ids: [Int]) async throws {
        try trackCall("unignoreTransactions")
    }

    func reclassifyTransaction(id: Int, _ body: ReclassifyRequest) async throws -> TransactionResponse {
        try trackCall("reclassifyTransaction")
        return configured(reclassifyTransactionResult)
    }

    func markAsSplit(id: Int, _ body: MarkAsSplitRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsSplit")
        return configured(markAsSplitResult)
    }

    func markAsLoan(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsLoan")
        return configured(markAsLoanResult)
    }

    func markAsDebt(id: Int, _ body: MarkAsDebtRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsDebt")
        return configured(markAsDebtResult)
    }

    func markAsInstallment(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsInstallment")
        return configured(markAsInstallmentResult)
    }

    func unclassifyTransaction(id: Int) async throws {
        try trackCall("unclassifyTransaction")
    }

    func unlinkTransaction(id: Int) async throws {
        try trackCall("unlinkTransaction")
    }

    func linkToEntry(_ body: BulkLinkRequest) async throws -> LinkedEntryResponse {
        try trackCall("linkToEntry")
        return configured(linkToEntryResult)
    }

    func mergeTransactions(_ body: TransactionMergeRequest) async throws -> TransactionResponse {
        try trackCall("mergeTransactions")
        return configured(mergeTransactionsResult)
    }

    func resolveCalibration(id: Int, _ body: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse {
        try trackCall("resolveCalibration")
        return configured(resolveCalibrationResult)
    }

    func bulkImport(_ body: BulkImportRequest) async throws -> BulkImportResponse {
        try trackCall("bulkImport")
        return configured(bulkImportResult)
    }

    func monthlySummary(month: String) async throws -> MonthlySummaryDict {
        try trackCall("monthlySummary")
        return configured(monthlySummaryResult)
    }

    // Categories

    func listCategories() async throws -> [CategoryWithSubcategories] {
        try trackCall("listCategories")
        return categoriesResult
    }

    func createCategory(_ body: CategoryCreate) async throws -> CategoryResponse {
        try trackCall("createCategory")
        return configured(categoryResult)
    }

    func updateCategory(id: Int, _ body: CategoryUpdate) async throws -> CategoryResponse {
        try trackCall("updateCategory")
        return configured(updateCategoryResult)
    }

    func deleteCategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws {
        try trackCall("deleteCategory")
    }

    func createSubcategory(categoryId: Int, _ body: SubcategoryCreate) async throws -> SubcategoryResponse {
        try trackCall("createSubcategory")
        return configured(createSubcategoryResult)
    }

    func updateSubcategory(id: Int, _ body: SubcategoryUpdate) async throws -> SubcategoryResponse {
        try trackCall("updateSubcategory")
        return configured(updateSubcategoryResult)
    }

    func deleteSubcategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws {
        try trackCall("deleteSubcategory")
    }

    // Linked Entries

    func listLinkedEntries(linkType: LinkType? = nil, status: LinkStatus? = nil) async throws -> [LinkedEntryWithDetails] {
        try trackCall("listLinkedEntries")
        return linkedEntriesResult
    }

    func pendingEntries() async throws -> [LinkedEntryWithDetails] {
        try trackCall("pendingEntries")
        return pendingEntriesResult
    }

    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails {
        try trackCall("getLinkedEntry")
        return configured(linkedEntryResult)
    }

    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails {
        try trackCall("getLinkedEntryByTransaction")
        return configured(linkedEntryByTransactionResult)
    }

    func createLinkedEntry(_ body: LinkedEntryCreate) async throws -> LinkedEntryResponse {
        try trackCall("createLinkedEntry")
        return configured(createLinkedEntryResult)
    }

    func updateLinkedEntry(id: Int, _ body: LinkedEntryUpdate) async throws -> LinkedEntryResponse {
        try trackCall("updateLinkedEntry")
        return configured(updateLinkedEntryResult)
    }

    func deleteLinkedEntry(id: Int) async throws {
        try trackCall("deleteLinkedEntry")
    }

    func linkTransaction(entryId: Int, _ body: LinkTransactionRequest) async throws -> LinkedEntryResponse {
        try trackCall("linkTransaction")
        return configured(linkTransactionResult)
    }

    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse {
        try trackCall("unlinkTransactionFromEntry")
        return configured(unlinkTransactionFromEntryResult)
    }

    func summaryOwed() async throws -> OwedSummary {
        try trackCall("summaryOwed")
        return configured(owedResult)
    }

    func summaryDebt() async throws -> DebtSummary {
        try trackCall("summaryDebt")
        return configured(debtResult)
    }

    // Budgets

    func listBudgets(year: Int? = nil, month: Int? = nil, categoryId: Int? = nil) async throws -> [BudgetWithCategory] {
        try trackCall("listBudgets")
        return budgetsResult
    }

    func createBudget(_ body: BudgetCreate) async throws -> BudgetResponse {
        try trackCall("createBudget")
        return configured(budgetResult)
    }

    func updateBudget(id: Int, _ body: BudgetUpdate) async throws -> BudgetResponse {
        try trackCall("updateBudget")
        return configured(updateBudgetResult)
    }

    func deleteBudget(id: Int) async throws {
        try trackCall("deleteBudget")
    }

    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String? = nil) async throws -> MonthlySummaryResponse {
        try trackCall("budgetMonthlySummary")
        return configured(monthlyBudgetSummaryResult)
    }

    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse {
        try trackCall("budgetDailySummary")
        return configured(dailyBudgetSummaryResult)
    }
}
