import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {

    private(set) var categories: [CategoryWithSubcategories] = []
    private(set) var isLoading = false
    private(set) var lastErrorMessage: String?

    private var apiClient: (any APIClientProtocol)?

    func configure(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let apiClient else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            categories = try await apiClient.listCategories()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            print("Failed to refresh categories: \(error)")
        }
    }

    func category(for id: Int) -> CategoryWithSubcategories? {
        categories.first { $0.id == id }
    }

    func subcategory(for id: Int) -> SubcategoryResponse? {
        for category in categories {
            if let subcategory = category.subcategories.first(where: { $0.id == id }) {
                return subcategory
            }
        }
        return nil
    }
}
