import Foundation

struct BudgetResponse: Codable, Identifiable, Sendable {
    let id: Int
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
    let createdAt: String
    let updatedAt: String
}

struct BudgetWithCategory: Codable, Identifiable, Sendable {
    let id: Int
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
    let createdAt: String
    let updatedAt: String
    let categoryName: String?
    let categoryEmoji: String?
}

struct BudgetCreate: Codable, Sendable {
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
}

struct BudgetUpdate: Codable, Sendable {
    var amount: Decimal?
}

struct CategorySummary: Codable, Identifiable, Sendable {
    let categoryId: Int
    let categoryName: String
    let emoji: String?
    let color: String?
    let budget: Double
    let actual: Double
    let percentage: Double
    let periods: [Double]
    let subcategories: [SubcategorySummary]

    var id: Int { categoryId }
}

struct SubcategorySummary: Codable, Identifiable, Sendable {
    let subcategoryId: Int
    let subcategoryName: String
    let actual: Double
    let periods: [Double]

    var id: Int { subcategoryId }
}

struct MonthlySummaryResponse: Codable, Sendable {
    let year: Int
    let month: Int
    let categories: [CategorySummary]
    let totalBudget: Decimal
    let totalActual: Decimal
    let periodBoundaries: [Int]
}

struct DailyCategoryData: Codable, Identifiable, Sendable {
    let categoryId: Int
    let categoryName: String
    let emoji: String?
    let color: String?
    let budget: Double
    let dailyAmounts: [Double]
    let subcategories: [DailySubcategoryData]

    var id: Int { categoryId }
}

struct DailySubcategoryData: Codable, Identifiable, Sendable {
    let subcategoryId: Int
    let subcategoryName: String
    let dailyAmounts: [Double]

    var id: Int { subcategoryId }
}

struct DailySummaryResponse: Codable, Sendable {
    let year: Int
    let month: Int
    let daysInMonth: Int
    let categories: [DailyCategoryData]
}
