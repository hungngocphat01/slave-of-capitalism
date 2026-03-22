import Foundation

struct TransactionResponse: Codable, Identifiable, Sendable {
    let id: Int
    let date: String
    let time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    let description: String?
    let categoryId: Int?
    let subcategoryId: Int?
    let pairedTransactionId: Int?
    let isIgnored: Bool
    let isCalibration: Bool
    let createdAt: String
    let updatedAt: String
}

struct TransactionWithDetails: Codable, Identifiable, Sendable {
    let id: Int
    let date: String
    let time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    let description: String?
    let categoryId: Int?
    let subcategoryId: Int?
    let pairedTransactionId: Int?
    let isIgnored: Bool
    let isCalibration: Bool
    let createdAt: String
    let updatedAt: String
    let walletName: String?
    let walletType: String?
    let categoryName: String?
    let subcategoryName: String?
    let hasLinkedEntry: Bool
    let isLinkedToEntry: Bool
    let linkedEntry: LinkedEntryResponse?
}

struct TransactionCreate: Codable, Sendable {
    let date: String
    var time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
    var isIgnored: Bool = false
    var isCalibration: Bool = false
    var allowLargeCacheRebuild: Bool = false
}

struct TransactionUpdate: Codable, Sendable {
    var date: String?
    var time: String?
    var walletId: Int?
    var direction: TransactionDirection?
    var amount: Decimal?
    var classification: TransactionClassification?
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
    var isIgnored: Bool?
    var isCalibration: Bool?
    var allowLargeCacheRebuild: Bool?
}

struct ReclassifyRequest: Codable, Sendable {
    let classification: TransactionClassification
}

struct BulkActionRequest: Codable, Sendable {
    let transactionIds: [Int]
}

struct BulkLinkRequest: Codable, Sendable {
    let transactionIds: [Int]
    let linkedEntryId: Int
}

struct TransactionMergeRequest: Codable, Sendable {
    let transactionIds: [Int]
    let date: String
    let description: String
    var categoryId: Int?
    var subcategoryId: Int?
}

struct BulkImportRequest: Codable, Sendable {
    let items: [TransactionCreate]
}

struct BulkImportResponse: Codable, Sendable {
    let importedCount: Int
    let message: String
}

struct MonthlySummaryDict: Codable, Sendable {
    let month: String
    let totalExpense: Decimal
    let categoryBreakdown: [String: Decimal]
}

struct ResolveCalibrationRequest: Codable, Sendable {
    let date: String
    var time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
}

struct ResolveCalibrationResponse: Codable, Sendable {
    let newTransaction: TransactionResponse
    let calibrationDeleted: Bool
    let updatedCalibration: TransactionResponse?
}

struct CalibrateWalletRequest: Codable, Sendable {
    let correctBalance: Decimal
    let miscCategoryId: Int
}
