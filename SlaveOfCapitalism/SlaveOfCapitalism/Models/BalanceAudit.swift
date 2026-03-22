import Foundation

struct BalanceAuditResponse: Codable, Identifiable, Sendable {
    let id: Int
    let date: String
    let balances: [String: Double?]
    let debts: Decimal
    let owed: Decimal
    let netPosition: Decimal
    let createdAt: String
    let updatedAt: String
}

struct BalanceAuditCreate: Codable, Sendable {
    let date: String
    var balances: [String: Double?]?
    var debts: Decimal?
    var owed: Decimal?
    var netPosition: Decimal?
}
