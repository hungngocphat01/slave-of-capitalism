import Foundation

struct CategoryMapEntry: Codable {
    let categoryId: Int
    var subcategoryId: Int?
}

/// Separated import payloads: regular transactions go through bulkImport,
/// wallet charges go through individual wallet transfer calls.
struct PayPayImportPayload {
    let transactions: [TransactionCreate]
    let transfers: [WalletTransferRequest]
}

enum PayPayTransformer {
    // Map wallet names to wallet IDs (exact + substring match)
    static func mapWallets(rows: inout [TransformedRow], mapping: [String: Int]) {
        for i in rows.indices {
            let walletName = rows[i].wallet
            // Exact match first
            if let id = mapping[walletName] {
                rows[i].walletId = id
                continue
            }
            // Substring match
            for (key, id) in mapping {
                if walletName.contains(key) {
                    rows[i].walletId = id
                    break
                }
            }
        }
    }

    // Convert transformed rows to import payload
    // BulkImportRequest only accepts [TransactionCreate], so transfers are separated out.
    static func buildPayload(
        rows: [TransformedRow],
        walletMapping: [String: Int],
        categoryMapping: [String: CategoryMapEntry]
    ) -> PayPayImportPayload {
        var transactions: [TransactionCreate] = []
        var transfers: [WalletTransferRequest] = []

        for row in rows {
            switch row.method {
            case "bank_transfer":
                // Ignored expense — treated as a regular transaction flagged as ignored
                transactions.append(TransactionCreate(
                    date: row.date,
                    time: row.time,
                    walletId: row.walletId ?? 0,
                    direction: .outflow,
                    amount: Decimal(row.amount),
                    classification: .expense,
                    description: row.description,
                    isIgnored: true
                ))

            case "charge":
                // Wallet transfer from charge source to PayPay balance wallet
                let paypayBalanceId = walletMapping["PayPay残高"] ?? 0
                transfers.append(WalletTransferRequest(
                    fromWalletId: row.walletId ?? 0,
                    toWalletId: paypayBalanceId,
                    amount: Decimal(row.amount),
                    description: row.description,
                    date: row.date,
                    time: row.time
                ))

            default:
                // Regular transaction
                let catEntry = row.category.flatMap { categoryMapping[$0] }
                transactions.append(TransactionCreate(
                    date: row.date,
                    time: row.time,
                    walletId: row.walletId ?? 0,
                    direction: row.direction == "inflow" ? .inflow : .outflow,
                    amount: Decimal(row.amount),
                    classification: row.direction == "inflow" ? .income : .expense,
                    description: row.description,
                    categoryId: catEntry?.categoryId,
                    subcategoryId: catEntry?.subcategoryId
                ))
            }
        }

        return PayPayImportPayload(transactions: transactions, transfers: transfers)
    }
}
