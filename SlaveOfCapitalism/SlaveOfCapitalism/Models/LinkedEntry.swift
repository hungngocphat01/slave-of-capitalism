import Foundation

struct LinkedEntryResponse: Codable, Identifiable, Sendable {
    let id: Int
    let linkType: LinkType
    let primaryTransactionId: Int
    let counterpartyName: String
    let totalAmount: Decimal
    let userAmount: Decimal?
    let pendingAmount: Decimal
    let status: LinkStatus
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let linkedTransactions: [LinkedTransactionResponse]
}

struct LinkedEntryWithDetails: Codable, Identifiable, Sendable {
    let id: Int
    let linkType: LinkType
    let primaryTransactionId: Int
    let counterpartyName: String
    let totalAmount: Decimal
    let userAmount: Decimal?
    let pendingAmount: Decimal
    let status: LinkStatus
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let linkedTransactions: [LinkedTransactionResponse]
    let primaryTransactionDescription: String?
    let primaryTransactionDate: String?
    let settledAmount: Decimal
}

struct LinkedTransactionResponse: Codable, Identifiable, Sendable {
    let id: Int
    let linkedEntryId: Int
    let transactionId: Int
    let amount: Decimal
    let createdAt: String
    let date: String?
    let description: String?
}

struct LinkedEntryCreate: Codable, Sendable {
    let primaryTransactionId: Int
    let linkType: LinkType
    let counterpartyName: String
    var userAmount: Decimal?
    var notes: String?
}

struct LinkedEntryUpdate: Codable, Sendable {
    var counterpartyName: String?
    var userAmount: Decimal?
    var notes: String?
}

struct LinkTransactionRequest: Codable, Sendable {
    let transactionId: Int
}

struct MarkAsSplitRequest: Codable, Sendable {
    let counterpartyName: String
    let userAmount: Decimal
    var notes: String?
}

struct MarkAsLoanRequest: Codable, Sendable {
    let counterpartyName: String
    var notes: String?
}

struct MarkAsDebtRequest: Codable, Sendable {
    let counterpartyName: String
    var notes: String?
}

struct OwedSummary: Codable, Sendable {
    let totalOwed: Decimal
    let pendingCount: Int
}

struct DebtSummary: Codable, Sendable {
    let totalDebt: Decimal
    let pendingCount: Int
}
