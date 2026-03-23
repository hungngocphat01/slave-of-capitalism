import Foundation

struct RawCsvRow {
    let transactionDate: String    // 取引日
    let withdrawalAmount: String   // 出金金額（円）
    let depositAmount: String      // 入金金額（円）
    let transactionContent: String // 取引内容
    let counterparty: String       // 取引先
    let transactionMethod: String  // 取引方法
    let transactionId: String      // 取引番号
}

struct TransformedRow: Identifiable {
    let id: String
    let date: String       // yyyy-MM-dd
    let time: String       // HH:mm:ss
    let dayOfWeek: Int     // 0-6, Sunday=0
    let amount: Double
    let direction: String  // "inflow" or "outflow"
    let method: String     // payment, received, sent, charge, bank_transfer
    let description: String
    let wallet: String
    var category: String?
    var walletId: Int?
}

enum PayPayParser {
    static func parseCSV(_ text: String) -> [RawCsvRow] {
        // Strip BOM
        var content = text
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }

        // Split lines, handling \r\n
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 2 else { return [] }

        // Parse header to find column indices
        let headers = parseCSVLine(lines[0])
        guard let dateIdx = headers.firstIndex(of: "取引日"),
              let withdrawIdx = headers.firstIndex(of: "出金金額（円）"),
              let depositIdx = headers.firstIndex(of: "入金金額（円）"),
              let contentIdx = headers.firstIndex(of: "取引内容"),
              let counterpartyIdx = headers.firstIndex(of: "取引先"),
              let methodIdx = headers.firstIndex(of: "取引方法"),
              let idIdx = headers.firstIndex(of: "取引番号") else {
            return []
        }

        var rows: [RawCsvRow] = []
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let fields = parseCSVLine(line)
            guard fields.count > max(dateIdx, withdrawIdx, depositIdx, contentIdx, counterpartyIdx, methodIdx, idIdx) else { continue }
            rows.append(RawCsvRow(
                transactionDate: fields[dateIdx],
                withdrawalAmount: fields[withdrawIdx],
                depositAmount: fields[depositIdx],
                transactionContent: fields[contentIdx],
                counterparty: fields[counterpartyIdx],
                transactionMethod: fields[methodIdx],
                transactionId: fields[idIdx]
            ))
        }
        return rows
    }

    // Hand-rolled CSV line parser with quote handling
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = line.makeIterator()

        while let ch = chars.next() {
            if inQuotes {
                if ch == "\"" {
                    // Check for escaped quote
                    if let next = chars.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
        }
        fields.append(current)
        return fields
    }

    // Transform raw rows to app domain
    static func transform(_ rows: [RawCsvRow]) -> [TransformedRow] {
        rows.compactMap { row in
            // Parse datetime: "2025/12/10 12:17:20"
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            guard let dt = formatter.date(from: row.transactionDate) else { return nil }

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "HH:mm:ss"

            let withdraw = parseJapaneseNumber(row.withdrawalAmount)
            let deposit = parseJapaneseNumber(row.depositAmount)
            let amount = max(withdraw, deposit)
            let direction = deposit > 0 ? "inflow" : "outflow"

            return TransformedRow(
                id: row.transactionId,
                date: dateFmt.string(from: dt),
                time: timeFmt.string(from: dt),
                dayOfWeek: Calendar.current.component(.weekday, from: dt) - 1, // 0=Sunday
                amount: amount,
                direction: direction,
                method: translateMethod(row.transactionContent),
                description: row.counterparty,
                wallet: row.transactionMethod
            )
        }
    }

    static func parseJapaneseNumber(_ value: String) -> Double {
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty || cleaned == "-" { return 0 }
        return Double(cleaned.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static let methodTranslations: [String: String] = [
        "支払い": "payment",
        "受け取った金額": "received",
        "送った金額": "sent",
        "チャージ": "charge",
        "口座送金": "bank_transfer"
    ]

    static func translateMethod(_ japanese: String) -> String {
        methodTranslations[japanese] ?? japanese
    }
}
