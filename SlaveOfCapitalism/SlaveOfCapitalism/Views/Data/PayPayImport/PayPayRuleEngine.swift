import Foundation

struct CompiledCondition {
    let field: String
    let op: String    // >, <, >=, <=, =, *=
    let value: String // stored as string, compared contextually
}

struct CompiledRule {
    let conditions: [CompiledCondition]
    let category: String
}

enum PayPayRuleEngine {
    static func compile(_ ruleLines: [String]) -> [CompiledRule] {
        ruleLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }

            let parts = trimmed.components(separatedBy: "->")
            guard parts.count == 2 else { return nil }

            let condStr = parts[0].trimmingCharacters(in: .whitespaces)
            let category = parts[1].trimmingCharacters(in: .whitespaces)

            let conditions = condStr.components(separatedBy: ",").compactMap { cond -> CompiledCondition? in
                let c = cond.trimmingCharacters(in: .whitespaces)
                for op in [">=", "<=", "*=", ">", "<", "="] {
                    if let range = c.range(of: " \(op) ") {
                        let field = String(c[c.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let val = String(c[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        return CompiledCondition(field: field, op: op, value: val)
                    }
                }
                return nil
            }

            return CompiledRule(conditions: conditions, category: category)
        }
    }

    static func execute(rules: [CompiledRule], rows: inout [TransformedRow]) {
        for i in rows.indices {
            // Auto-rules: charge and bank_transfer get no category
            if rows[i].method == "charge" || rows[i].method == "bank_transfer" {
                rows[i].category = ""
                continue
            }

            // Apply user rules (first match wins)
            for rule in rules {
                guard rows[i].category == nil else { break }

                let hasMethodCondition = rule.conditions.contains { $0.field == "method" }
                var allMatch = true

                for cond in rule.conditions {
                    if !matchCondition(cond, row: rows[i]) {
                        allMatch = false
                        break
                    }
                }

                // If no explicit method condition, default to payment-only
                if allMatch && !hasMethodCondition && rows[i].method != "payment" {
                    allMatch = false
                }

                if allMatch {
                    rows[i].category = rule.category
                }
            }
        }
    }

    private static func matchCondition(_ cond: CompiledCondition, row: TransformedRow) -> Bool {
        let rowValue = fieldValue(cond.field, row: row)

        switch cond.op {
        case "=": return rowValue == cond.value
        case "*=": return rowValue.contains(cond.value)
        case ">", "<", ">=", "<=":
            if let numRow = Double(rowValue), let numCond = Double(cond.value) {
                switch cond.op {
                case ">": return numRow > numCond
                case "<": return numRow < numCond
                case ">=": return numRow >= numCond
                case "<=": return numRow <= numCond
                default: return false
                }
            }
            return rowValue > cond.value // string comparison fallback
        default: return false
        }
    }

    private static func fieldValue(_ field: String, row: TransformedRow) -> String {
        switch field {
        case "id": return row.id
        case "date": return row.date
        case "time": return row.time
        case "dayofweek": return "\(row.dayOfWeek)"
        case "amount": return "\(row.amount)"
        case "direction": return row.direction
        case "method": return row.method
        case "description": return row.description
        case "wallet": return row.wallet
        default: return ""
        }
    }
}
