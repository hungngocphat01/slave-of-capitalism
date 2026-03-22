import Foundation

struct CategoryResponse: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let emoji: String?
    let color: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
}

struct CategoryWithSubcategories: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let emoji: String?
    let color: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
    let subcategories: [SubcategoryResponse]
}

struct SubcategoryResponse: Codable, Identifiable, Sendable {
    let id: Int
    let categoryId: Int
    let name: String
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
}

struct CategoryCreate: Codable, Sendable {
    let name: String
    var emoji: String?
    var color: String?
}

struct CategoryUpdate: Codable, Sendable {
    var name: String?
    var emoji: String?
    var color: String?
}

struct SubcategoryCreate: Codable, Sendable {
    let name: String
}

struct SubcategoryUpdate: Codable, Sendable {
    var name: String?
}
