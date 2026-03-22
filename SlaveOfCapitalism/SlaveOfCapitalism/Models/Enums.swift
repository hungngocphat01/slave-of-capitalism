import Foundation

enum TransactionDirection: String, Codable, CaseIterable, Sendable {
    case inflow, outflow, reserved
}

enum TransactionClassification: String, Codable, CaseIterable, Sendable {
    case expense, income, lend, borrow
    case debtCollection = "debt_collection"
    case loanRepayment = "loan_repayment"
    case splitPayment = "split_payment"
    case transfer
    case installment
    case installmtChrge = "installmt_chrge"
}

enum WalletType: String, Codable, CaseIterable, Sendable {
    case normal, credit
}

enum LinkType: String, Codable, CaseIterable, Sendable {
    case splitPayment = "split_payment"
    case loan, debt, installment
}

enum LinkStatus: String, Codable, CaseIterable, Sendable {
    case pending, partial, settled
}
