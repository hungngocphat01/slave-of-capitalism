import Foundation

struct WalletResponse: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let walletType: WalletType
    let creditLimit: Decimal
    let emoji: String?
    let createdAt: String
    let updatedAt: String
}

struct WalletWithBalance: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let walletType: WalletType
    let creditLimit: Decimal
    let emoji: String?
    let createdAt: String
    let updatedAt: String
    let currentBalance: Decimal
    let availableCredit: Decimal?
}

struct WalletCreate: Codable, Sendable {
    let name: String
    var walletType: WalletType = .normal
    var creditLimit: Decimal = 0
    var emoji: String?
    var initialBalance: Decimal = 0
}

struct WalletUpdate: Codable, Sendable {
    var name: String?
    var walletType: WalletType?
    var creditLimit: Decimal?
    var emoji: String?
}

struct WalletTransferRequest: Codable, Sendable {
    let fromWalletId: Int
    let toWalletId: Int
    let amount: Decimal
    let description: String
    let date: String
    var time: String?
}

struct WalletTransferResponse: Codable, Sendable {
    let outflowTransaction: TransactionResponse
    let inflowTransaction: TransactionResponse
}
