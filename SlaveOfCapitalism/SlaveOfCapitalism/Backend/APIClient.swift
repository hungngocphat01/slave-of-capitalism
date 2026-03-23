import Foundation

// MARK: - APIError

enum APIError: LocalizedError {
    case notFound
    case validationError(String)
    case serverError(String)
    case networkError(Error)
    case backendNotReady
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Resource not found"
        case .validationError(let msg): return "Validation error: \(msg)"
        case .serverError(let msg): return "Server error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .backendNotReady: return "Backend is not ready"
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        }
    }
}

// MARK: - APIClientProtocol

protocol APIClientProtocol: AnyObject {
    // Wallets
    func listWallets() async throws -> [WalletWithBalance]
    func getWallet(id: Int) async throws -> WalletWithBalance
    func createWallet(_ body: WalletCreate) async throws -> WalletResponse
    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse
    func deleteWallet(id: Int) async throws
    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse
    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse
    func getAudits() async throws -> [BalanceAuditResponse]
    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse

    // Transactions
    func listTransactions(walletId: Int?, categoryId: Int?, month: String?, direction: TransactionDirection?, classification: TransactionClassification?) async throws -> [TransactionWithDetails]
    func getTransaction(id: Int) async throws -> TransactionWithDetails
    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse
    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse
    func deleteTransaction(id: Int) async throws
    func deleteTransactions(ids: [Int]) async throws
    func ignoreTransactions(ids: [Int]) async throws
    func unignoreTransactions(ids: [Int]) async throws
    func reclassifyTransaction(id: Int, _ body: ReclassifyRequest) async throws -> TransactionResponse
    func markAsSplit(id: Int, _ body: MarkAsSplitRequest) async throws -> LinkedEntryResponse
    func markAsLoan(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse
    func markAsDebt(id: Int, _ body: MarkAsDebtRequest) async throws -> LinkedEntryResponse
    func markAsInstallment(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse
    func unclassifyTransaction(id: Int) async throws
    func unlinkTransaction(id: Int) async throws
    func linkToEntry(_ body: BulkLinkRequest) async throws -> LinkedEntryResponse
    func mergeTransactions(_ body: TransactionMergeRequest) async throws -> TransactionResponse
    func resolveCalibration(id: Int, _ body: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse
    func bulkImport(_ body: BulkImportRequest) async throws -> BulkImportResponse
    func monthlySummary(month: String) async throws -> MonthlySummaryDict

    // Categories
    func listCategories() async throws -> [CategoryWithSubcategories]
    func createCategory(_ body: CategoryCreate) async throws -> CategoryResponse
    func updateCategory(id: Int, _ body: CategoryUpdate) async throws -> CategoryResponse
    func deleteCategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws
    func createSubcategory(categoryId: Int, _ body: SubcategoryCreate) async throws -> SubcategoryResponse
    func updateSubcategory(id: Int, _ body: SubcategoryUpdate) async throws -> SubcategoryResponse
    func deleteSubcategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async throws

    // Linked Entries
    func listLinkedEntries(linkType: LinkType?, status: LinkStatus?) async throws -> [LinkedEntryWithDetails]
    func pendingEntries() async throws -> [LinkedEntryWithDetails]
    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails
    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails
    func createLinkedEntry(_ body: LinkedEntryCreate) async throws -> LinkedEntryResponse
    func updateLinkedEntry(id: Int, _ body: LinkedEntryUpdate) async throws -> LinkedEntryResponse
    func deleteLinkedEntry(id: Int) async throws
    func linkTransaction(entryId: Int, _ body: LinkTransactionRequest) async throws -> LinkedEntryResponse
    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse
    func summaryOwed() async throws -> OwedSummary
    func summaryDebt() async throws -> DebtSummary

    // Budgets
    func listBudgets(year: Int?, month: Int?, categoryId: Int?) async throws -> [BudgetWithCategory]
    func createBudget(_ body: BudgetCreate) async throws -> BudgetResponse
    func updateBudget(id: Int, _ body: BudgetUpdate) async throws -> BudgetResponse
    func deleteBudget(id: Int) async throws
    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String?) async throws -> MonthlySummaryResponse
    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse

    // Health
    func healthCheck() async throws -> Bool
}

// MARK: - APIClient

@Observable
final class APIClient: APIClientProtocol {

    var baseURL: URL

    private let session: URLSession
    private let encoder: JSONEncoder

    init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Generic Helpers

    private func buildURL(path: String, query: [(String, String)] = []) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components.url!
    }

    private func request<T: Decodable>(_ method: String, path: String, query: [(String, String)] = []) async throws -> T {
        let url = buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(req)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, path: String, body: B, query: [(String, String)] = []) async throws -> T {
        let url = buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.networkError(error)
        }
        return try await perform(req)
    }

    private func requestVoid(_ method: String, path: String, query: [(String, String)] = []) async throws {
        let url = buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        try await performVoid(req)
    }

    private func requestVoid<B: Encodable>(_ method: String, path: String, body: B) async throws {
        let url = buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.networkError(error)
        }
        try await performVoid(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }
        try validateResponse(response, data: data)
        do {
            return try APIModelDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performVoid(_ req: URLRequest) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }
        try validateResponse(response, data: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299:
            return
        case 404:
            throw APIError.notFound
        case 422:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Validation failed"
            throw APIError.validationError(msg)
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(msg)
        }
    }

    // MARK: - Health

    func healthCheck() async throws -> Bool {
        struct HealthResponse: Decodable { let status: String }
        let resp: HealthResponse = try await request("GET", path: "api/health")
        let normalized = resp.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ok" || normalized == "healthy"
    }

    // MARK: - Wallets

    func listWallets() async throws -> [WalletWithBalance] {
        try await request("GET", path: "api/wallets/")
    }

    func getWallet(id: Int) async throws -> WalletWithBalance {
        try await request("GET", path: "api/wallets/\(id)")
    }

    func createWallet(_ body: WalletCreate) async throws -> WalletResponse {
        try await request("POST", path: "api/wallets/", body: body)
    }

    func updateWallet(id: Int, _ body: WalletUpdate) async throws -> WalletResponse {
        try await request("PUT", path: "api/wallets/\(id)", body: body)
    }

    func deleteWallet(id: Int) async throws {
        try await requestVoid("DELETE", path: "api/wallets/\(id)")
    }

    func transfer(_ body: WalletTransferRequest) async throws -> WalletTransferResponse {
        try await request("POST", path: "api/wallets/transfer", body: body)
    }

    func calibrateWallet(id: Int, _ body: CalibrateWalletRequest) async throws -> TransactionResponse {
        try await request("POST", path: "api/wallets/\(id)/calibrate", body: body)
    }

    func getAudits() async throws -> [BalanceAuditResponse] {
        try await request("GET", path: "api/wallets/audits")
    }

    func createAudit(_ body: BalanceAuditCreate) async throws -> BalanceAuditResponse {
        try await request("POST", path: "api/wallets/audits", body: body)
    }

    // MARK: - Transactions

    func listTransactions(
        walletId: Int? = nil,
        categoryId: Int? = nil,
        month: String? = nil,
        direction: TransactionDirection? = nil,
        classification: TransactionClassification? = nil
    ) async throws -> [TransactionWithDetails] {
        var query: [(String, String)] = []
        if let v = walletId { query.append(("wallet_id", "\(v)")) }
        if let v = categoryId { query.append(("category_id", "\(v)")) }
        if let v = month { query.append(("month", v)) }
        if let v = direction { query.append(("direction", v.rawValue)) }
        if let v = classification { query.append(("classification", v.rawValue)) }
        return try await request("GET", path: "api/transactions/", query: query)
    }

    func getTransaction(id: Int) async throws -> TransactionWithDetails {
        try await request("GET", path: "api/transactions/\(id)")
    }

    func createTransaction(_ body: TransactionCreate) async throws -> TransactionResponse {
        try await request("POST", path: "api/transactions/", body: body)
    }

    func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse {
        try await request("PUT", path: "api/transactions/\(id)", body: body)
    }

    func deleteTransaction(id: Int) async throws {
        try await requestVoid("DELETE", path: "api/transactions/\(id)")
    }

    func deleteTransactions(ids: [Int]) async throws {
        let body = BulkActionRequest(transactionIds: ids)
        try await requestVoid("DELETE", path: "api/transactions/", body: body)
    }

    func ignoreTransactions(ids: [Int]) async throws {
        let body = BulkActionRequest(transactionIds: ids)
        try await requestVoid("POST", path: "api/transactions/ignore", body: body)
    }

    func unignoreTransactions(ids: [Int]) async throws {
        let body = BulkActionRequest(transactionIds: ids)
        try await requestVoid("POST", path: "api/transactions/unignore", body: body)
    }

    func reclassifyTransaction(id: Int, _ body: ReclassifyRequest) async throws -> TransactionResponse {
        try await request("POST", path: "api/transactions/\(id)/reclassify", body: body)
    }

    func markAsSplit(id: Int, _ body: MarkAsSplitRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/transactions/\(id)/mark-split", body: body)
    }

    func markAsLoan(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/transactions/\(id)/mark-loan", body: body)
    }

    func markAsDebt(id: Int, _ body: MarkAsDebtRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/transactions/\(id)/mark-debt", body: body)
    }

    func markAsInstallment(id: Int, _ body: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/transactions/\(id)/mark-installment", body: body)
    }

    func unclassifyTransaction(id: Int) async throws {
        try await requestVoid("POST", path: "api/transactions/\(id)/unclassify")
    }

    func unlinkTransaction(id: Int) async throws {
        try await requestVoid("POST", path: "api/transactions/\(id)/unlink")
    }

    func linkToEntry(_ body: BulkLinkRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/transactions/link", body: body)
    }

    func mergeTransactions(_ body: TransactionMergeRequest) async throws -> TransactionResponse {
        try await request("POST", path: "api/transactions/merge", body: body)
    }

    func resolveCalibration(id: Int, _ body: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse {
        try await request("POST", path: "api/transactions/\(id)/resolve", body: body)
    }

    func bulkImport(_ body: BulkImportRequest) async throws -> BulkImportResponse {
        try await request("POST", path: "api/transactions/bulk-import", body: body)
    }

    func monthlySummary(month: String) async throws -> MonthlySummaryDict {
        try await request("GET", path: "api/transactions/monthly-summary/", query: [("month", month)])
    }

    // MARK: - Categories

    func listCategories() async throws -> [CategoryWithSubcategories] {
        try await request("GET", path: "api/categories/")
    }

    func createCategory(_ body: CategoryCreate) async throws -> CategoryResponse {
        try await request("POST", path: "api/categories/", body: body)
    }

    func updateCategory(id: Int, _ body: CategoryUpdate) async throws -> CategoryResponse {
        try await request("PUT", path: "api/categories/\(id)", body: body)
    }

    func deleteCategory(id: Int, replacementCategoryId: Int? = nil, replacementSubcategoryId: Int? = nil) async throws {
        var query: [(String, String)] = []
        if let v = replacementCategoryId { query.append(("replacement_category_id", "\(v)")) }
        if let v = replacementSubcategoryId { query.append(("replacement_subcategory_id", "\(v)")) }
        try await requestVoid("DELETE", path: "api/categories/\(id)", query: query)
    }

    func createSubcategory(categoryId: Int, _ body: SubcategoryCreate) async throws -> SubcategoryResponse {
        try await request("POST", path: "api/categories/\(categoryId)/subcategories", body: body)
    }

    func updateSubcategory(id: Int, _ body: SubcategoryUpdate) async throws -> SubcategoryResponse {
        try await request("PUT", path: "api/categories/subcategories/\(id)", body: body)
    }

    func deleteSubcategory(id: Int, replacementCategoryId: Int? = nil, replacementSubcategoryId: Int? = nil) async throws {
        var query: [(String, String)] = []
        if let v = replacementCategoryId { query.append(("replacement_category_id", "\(v)")) }
        if let v = replacementSubcategoryId { query.append(("replacement_subcategory_id", "\(v)")) }
        try await requestVoid("DELETE", path: "api/categories/subcategories/\(id)", query: query)
    }

    // MARK: - Linked Entries

    func listLinkedEntries(linkType: LinkType? = nil, status: LinkStatus? = nil) async throws -> [LinkedEntryWithDetails] {
        var query: [(String, String)] = []
        if let v = linkType { query.append(("link_type", v.rawValue)) }
        if let v = status { query.append(("status", v.rawValue)) }
        return try await request("GET", path: "api/linked-entries/", query: query)
    }

    func pendingEntries() async throws -> [LinkedEntryWithDetails] {
        try await request("GET", path: "api/linked-entries/pending")
    }

    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails {
        try await request("GET", path: "api/linked-entries/\(id)")
    }

    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails {
        try await request("GET", path: "api/linked-entries/transaction/\(transactionId)")
    }

    func createLinkedEntry(_ body: LinkedEntryCreate) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/linked-entries/", body: body)
    }

    func updateLinkedEntry(id: Int, _ body: LinkedEntryUpdate) async throws -> LinkedEntryResponse {
        try await request("PUT", path: "api/linked-entries/\(id)", body: body)
    }

    func deleteLinkedEntry(id: Int) async throws {
        try await requestVoid("DELETE", path: "api/linked-entries/\(id)")
    }

    func linkTransaction(entryId: Int, _ body: LinkTransactionRequest) async throws -> LinkedEntryResponse {
        try await request("POST", path: "api/linked-entries/\(entryId)/link", body: body)
    }

    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse {
        try await request("DELETE", path: "api/linked-entries/\(entryId)/unlink/\(linkId)")
    }

    func summaryOwed() async throws -> OwedSummary {
        try await request("GET", path: "api/linked-entries/summary/owed")
    }

    func summaryDebt() async throws -> DebtSummary {
        try await request("GET", path: "api/linked-entries/summary/debt")
    }

    // MARK: - Budgets

    func listBudgets(year: Int? = nil, month: Int? = nil, categoryId: Int? = nil) async throws -> [BudgetWithCategory] {
        var query: [(String, String)] = []
        if let v = year { query.append(("year", "\(v)")) }
        if let v = month { query.append(("month", "\(v)")) }
        if let v = categoryId { query.append(("category_id", "\(v)")) }
        return try await request("GET", path: "api/budgets/", query: query)
    }

    func createBudget(_ body: BudgetCreate) async throws -> BudgetResponse {
        try await request("POST", path: "api/budgets/", body: body)
    }

    func updateBudget(id: Int, _ body: BudgetUpdate) async throws -> BudgetResponse {
        try await request("PUT", path: "api/budgets/\(id)", body: body)
    }

    func deleteBudget(id: Int) async throws {
        try await requestVoid("DELETE", path: "api/budgets/\(id)")
    }

    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String? = nil) async throws -> MonthlySummaryResponse {
        var query: [(String, String)] = []
        if let v = periodBoundaries { query.append(("period_boundaries", v)) }
        return try await request("GET", path: "api/budgets/summary/\(year)/\(month)", query: query)
    }

    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse {
        try await request("GET", path: "api/budgets/daily-summary/\(year)/\(month)")
    }
}
