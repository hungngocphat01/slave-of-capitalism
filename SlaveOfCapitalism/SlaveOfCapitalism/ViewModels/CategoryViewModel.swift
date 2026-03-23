import Foundation
import Observation

@MainActor
@Observable
final class CategoryViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var categories: [CategoryWithSubcategories] = []
    var selectedCategoryId: Int?
    private(set) var isLoading = false
    var error: APIError?

    var selectedCategory: CategoryWithSubcategories? {
        guard let id = selectedCategoryId else { return nil }
        return categories.first { $0.id == id }
    }

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            categories = try await apiClient.listCategories()
            error = nil
        } catch let apiError as APIError {
            categories = []
            error = apiError
        } catch {
            categories = []
            self.error = .networkError(error)
        }
    }

    func createCategory(name: String, emoji: String?, color: String?) async {
        do {
            _ = try await apiClient.createCategory(CategoryCreate(name: name, emoji: emoji, color: color))
            error = nil
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func updateCategory(id: Int, name: String?, emoji: String?, color: String?) async {
        do {
            _ = try await apiClient.updateCategory(id: id, CategoryUpdate(name: name, emoji: emoji, color: color))
            error = nil
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func deleteCategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async {
        do {
            try await apiClient.deleteCategory(id: id, replacementCategoryId: replacementCategoryId, replacementSubcategoryId: replacementSubcategoryId)
            error = nil
            if selectedCategoryId == id {
                selectedCategoryId = nil
            }
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func createSubcategory(categoryId: Int, name: String) async {
        do {
            _ = try await apiClient.createSubcategory(categoryId: categoryId, SubcategoryCreate(name: name))
            error = nil
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func updateSubcategory(id: Int, name: String?) async {
        do {
            _ = try await apiClient.updateSubcategory(id: id, SubcategoryUpdate(name: name))
            error = nil
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func deleteSubcategory(id: Int, replacementCategoryId: Int?, replacementSubcategoryId: Int?) async {
        do {
            try await apiClient.deleteSubcategory(id: id, replacementCategoryId: replacementCategoryId, replacementSubcategoryId: replacementSubcategoryId)
            error = nil
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }
}
