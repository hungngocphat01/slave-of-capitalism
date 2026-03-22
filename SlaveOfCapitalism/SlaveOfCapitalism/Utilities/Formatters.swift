import Foundation

enum Formatters {

    static func currency(_ amount: Decimal, symbol: String = "¥", decimals: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals

        let number = NSDecimalNumber(decimal: amount)
        let formattedAmount = formatter.string(from: number) ?? amount.description
        return "\(symbol)\(formattedAmount)"
    }

    static func date(_ isoString: String) -> String {
        isoString
    }

    static func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func monthYear(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        guard let date = calendar.date(from: components) else {
            return "\(month)/\(year)"
        }

        return formatter.string(from: date)
    }
}
