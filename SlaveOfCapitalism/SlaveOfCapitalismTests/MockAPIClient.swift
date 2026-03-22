import Foundation
@testable import SlaveOfCapitalism

enum MockAPIClientError: Error, Equatable {
    case unconfigured(String)
}

final class MockAPIClient: APIClientProtocol {
    var errorToThrow: Error?

    var lastCalledMethod: String?
    var callCount: [String: Int] = [:]
    var callLog: [String] = []

    // Wallets
    var walletsResult: [WalletWithBalance]?
    var walletResult: WalletWithBalance?
    var createWalletResult: WalletResponse?
    var updateWalletResult: WalletResponse?
    var transferResult: WalletTransferResponse?
    var calibrateWalletResult: TransactionResponse?
    var auditsResult: [BalanceAuditResponse]?
    var createAuditResult: BalanceAuditResponse?

    // Transactions
    var transactionsResult: [TransactionWithDetails]?
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
    var categoriesResult: [CategoryWithSubcategories]?
    var categoryResult: CategoryResponse?
    var updateCategoryResult: CategoryResponse?
    var createSubcategoryResult: SubcategoryResponse?
    var updateSubcategoryResult: SubcategoryResponse?

    // Linked Entries
    var linkedEntriesResult: [LinkedEntryWithDetails]?
    var pendingEntriesResult: [LinkedEntryWithDetails]?
    var linkedEntryResult: LinkedEntryWithDetails?
    var linkedEntryByTransactionResult: LinkedEntryWithDetails?
    var createLinkedEntryResult: LinkedEntryResponse?
    var updateLinkedEntryResult: LinkedEntryResponse?
    var linkTransactionResult: LinkedEntryResponse?
    var unlinkTransactionFromEntryResult: LinkedEntryResponse?
    var owedResult: OwedSummary?
    var debtResult: DebtSummary?

    // Budgets
    var budgetsResult: [BudgetWithCategory]?
    var budgetResult: BudgetResponse?
    var updateBudgetResult: BudgetResponse?
    var monthlyBudgetSummaryResult: MonthlySummaryResponse?
    var dailyBudgetSummaryResult: DailySummaryResponse?

    // Health
    var healthCheckResult = true

    private func trackCall(_ method: String) throws {
        lastCalledMethod = method
        callLog.append(method)
        callCount[method, default: 0] += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    private func configured<T>(_ value: T?, method: String) throws -> T {
        guard let value else {
            throw MockAPIClientError.unconfigured(method)
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
        return try configured(walletsResult, method: "listWallets")
    }

    func getWallet(id: Int) async throws -> WalletWithBalance {
        try trackCall("getWallet")
        return try configured(walletResult, method: "getWallet")
    }

    func createWallet(_ body: WalletCreate) async throws -> WalletResponse {
        try trackCall("createWallet")
        return try configured(createWalletResult, method: "createWallet")
    }

    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse {
        try trackCall("updateWallet")
        return try configured(updateWalletResult, method: "updateWallet")
    }

    func deleteWallet(id: Int) async throws {
        try trackCall("deleteWallet")
    }

    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse {
        try trackCall("transfer")
        return try configured(transferResult, method: "transfer")
    }

    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse {
        try trackCall("calibrateWallet")
        return try configured(calibrateWalletResult, method: "calibrateWallet")
    }

    func getAudits() async throws -> [BalanceAuditResponse] {
        try trackCall("getAudits")
        return try configured(auditsResult, method: "getAudits")
    }

    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse {
        try trackCall("createAudit")
        return try configured(createAuditResult, method: "createAudit")
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
        return try configured(transactionsResult, method: "listTransactions")
    }

    func getTransaction(id: Int) async throws -> TransactionWithDetails {
        try trackCall("getTransaction")
        return try configured(transactionResult, method: "getTransaction")
    }

    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse {
        try trackCall("createTransaction")
        return try configured(createTransactionResult, method: "createTransaction")
    }

    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse {
        try trackCall("updateTransaction")
        return try configured(updateTransactionResult, method: "updateTransaction")
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
        return try configured(reclassifyTransactionResult, method: "reclassifyTransaction")
    }

    func markAsSplit(id: Int, _ body: MarkAsSplitRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsSplit")
        return try configured(markAsSplitResult, method: "markAsSplit")
    }

    func markAsLoan(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsLoan")
        return try configured(markAsLoanResult, method: "markAsLoan")
    }

    func markAsDebt(id: Int, _ body: MarkAsDebtRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsDebt")
        return try configured(markAsDebtResult, method: "markAsDebt")
    }

    func markAsInstallment(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try trackCall("markAsInstallment")
        return try configured(markAsInstallmentResult, method: "markAsInstallment")
    }

    func unclassifyTransaction(id: Int) async throws {
        try trackCall("unclassifyTransaction")
    }

    func unlinkTransaction(id: Int) async throws {
        try trackCall("unlinkTransaction")
    }

    func linkToEntry(_ body: BulkLinkRequest) async throws -> LinkedEntryResponse {
        try trackCall("linkToEntry")
        return try configured(linkToEntryResult, method: "linkToEntry")
    }

    func mergeTransactions(_ body: TransactionMergeRequest) async throws -> TransactionResponse {
        try trackCall("mergeTransactions")
        return try configured(mergeTransactionsResult, method: "mergeTransactions")
    }

    func resolveCalibration(id: Int, _ body: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse {
        try trackCall("resolveCalibration")
        return try configured(resolveCalibrationResult, method: "resolveCalibration")
    }

    func bulkImport(_ body: BulkImportRequest) async throws -> BulkImportResponse {
        try trackCall("bulkImport")
        return try configured(bulkImportResult, method: "bulkImport")
    }

    func monthlySummary(month: String) async throws -> MonthlySummaryDict {
        try trackCall("monthlySummary")
        return try configured(monthlySummaryResult, method: "monthlySummary")
    }

    // Categories

    func listCategories() async throws -> [CategoryWithSubcategories] {
        try trackCall("listCategories")
        return try configured(categoriesResult, method: "listCategories")
    }

    func createCategory(_ body: CategoryCreate) async throws -> CategoryResponse {
        try trackCall("createCategory")
        return try configured(categoryResult, method: "createCategory")
    }

    func updateCategory(id: Int, _ body: CategoryUpdate) async throws -> CategoryResponse {
        try trackCall("updateCategory")
        return try configured(updateCategoryResult, method: "updateCategory")
    }

    func deleteCategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws {
        try trackCall("deleteCategory")
    }

    func createSubcategory(categoryId: Int, _ body: SubcategoryCreate) async throws -> SubcategoryResponse {
        try trackCall("createSubcategory")
        return try configured(createSubcategoryResult, method: "createSubcategory")
    }

    func updateSubcategory(id: Int, _ body: SubcategoryUpdate) async throws -> SubcategoryResponse {
        try trackCall("updateSubcategory")
        return try configured(updateSubcategoryResult, method: "updateSubcategory")
    }

    func deleteSubcategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws {
        try trackCall("deleteSubcategory")
    }

    // Linked Entries

    func listLinkedEntries(linkType: LinkType? = nil, status: LinkStatus? = nil) async throws -> [LinkedEntryWithDetails] {
        try trackCall("listLinkedEntries")
        return try configured(linkedEntriesResult, method: "listLinkedEntries")
    }

    func pendingEntries() async throws -> [LinkedEntryWithDetails] {
        try trackCall("pendingEntries")
        return try configured(pendingEntriesResult, method: "pendingEntries")
    }

    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails {
        try trackCall("getLinkedEntry")
        return try configured(linkedEntryResult, method: "getLinkedEntry")
    }

    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails {
        try trackCall("getLinkedEntryByTransaction")
        return try configured(linkedEntryByTransactionResult, method: "getLinkedEntryByTransaction")
    }

    func createLinkedEntry(_ body: LinkedEntryCreate) async throws -> LinkedEntryResponse {
        try trackCall("createLinkedEntry")
        return try configured(createLinkedEntryResult, method: "createLinkedEntry")
    }

    func updateLinkedEntry(id: Int, _ body: LinkedEntryUpdate) async throws -> LinkedEntryResponse {
        try trackCall("updateLinkedEntry")
        return try configured(updateLinkedEntryResult, method: "updateLinkedEntry")
    }

    func deleteLinkedEntry(id: Int) async throws {
        try trackCall("deleteLinkedEntry")
    }

    func linkTransaction(entryId: Int, _ body: LinkTransactionRequest) async throws -> LinkedEntryResponse {
        try trackCall("linkTransaction")
        return try configured(linkTransactionResult, method: "linkTransaction")
    }

    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse {
        try trackCall("unlinkTransactionFromEntry")
        return try configured(unlinkTransactionFromEntryResult, method: "unlinkTransactionFromEntry")
    }

    func summaryOwed() async throws -> OwedSummary {
        try trackCall("summaryOwed")
        return try configured(owedResult, method: "summaryOwed")
    }

    func summaryDebt() async throws -> DebtSummary {
        try trackCall("summaryDebt")
        return try configured(debtResult, method: "summaryDebt")
    }

    // Budgets

    func listBudgets(year: Int? = nil, month: Int? = nil, categoryId: Int? = nil) async throws -> [BudgetWithCategory] {
        try trackCall("listBudgets")
        return try configured(budgetsResult, method: "listBudgets")
    }

    func createBudget(_ body: BudgetCreate) async throws -> BudgetResponse {
        try trackCall("createBudget")
        return try configured(budgetResult, method: "createBudget")
    }

    func updateBudget(id: Int, _ body: BudgetUpdate) async throws -> BudgetResponse {
        try trackCall("updateBudget")
        return try configured(updateBudgetResult, method: "updateBudget")
    }

    func deleteBudget(id: Int) async throws {
        try trackCall("deleteBudget")
    }

    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String? = nil) async throws -> MonthlySummaryResponse {
        try trackCall("budgetMonthlySummary")
        return try configured(monthlyBudgetSummaryResult, method: "budgetMonthlySummary")
    }

    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse {
        try trackCall("budgetDailySummary")
        return try configured(dailyBudgetSummaryResult, method: "budgetDailySummary")
    }
}
