import XCTest
@testable import SlaveOfCapitalism

@MainActor
final class CategoryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeCategory(id: Int, name: String, isSystem: Bool = false, subcategories: [SubcategoryResponse] = []) -> CategoryWithSubcategories {
        CategoryWithSubcategories(
            id: id,
            name: name,
            emoji: nil,
            color: nil,
            isSystem: isSystem,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            subcategories: subcategories
        )
    }

    private func makeSubcategory(id: Int, categoryId: Int, name: String, isSystem: Bool = false) -> SubcategoryResponse {
        SubcategoryResponse(
            id: id,
            categoryId: categoryId,
            name: name,
            isSystem: isSystem,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeCategoryResponse(id: Int, name: String) -> CategoryResponse {
        CategoryResponse(
            id: id,
            name: name,
            emoji: nil,
            color: nil,
            isSystem: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    // MARK: - Load

    func testLoadFetchesCategories() async {
        let client = MockAPIClient()
        client.categoriesResult = [
            makeCategory(id: 1, name: "Food"),
            makeCategory(id: 2, name: "Transport")
        ]

        let vm = CategoryViewModel(apiClient: client)
        await vm.load()

        XCTAssertEqual(client.callLog, ["listCategories"])
        XCTAssertEqual(vm.categories.map(\.id), [1, 2])
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadStoresAPIError() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("DB unavailable")

        let vm = CategoryViewModel(apiClient: client)
        await vm.load()

        XCTAssertTrue(vm.categories.isEmpty)
        XCTAssertFalse(vm.isLoading)
        guard case .serverError(let msg)? = vm.error else {
            return XCTFail("Expected serverError, got \(String(describing: vm.error))")
        }
        XCTAssertEqual(msg, "DB unavailable")
    }

    // MARK: - selectedCategory computed property

    func testSelectedCategoryReturnsNilWhenNothingSelected() async {
        let client = MockAPIClient()
        client.categoriesResult = [makeCategory(id: 1, name: "Food")]
        let vm = CategoryViewModel(apiClient: client)
        await vm.load()

        XCTAssertNil(vm.selectedCategory)
    }

    func testSelectedCategoryReturnsMatchingCategory() async {
        let client = MockAPIClient()
        client.categoriesResult = [
            makeCategory(id: 1, name: "Food"),
            makeCategory(id: 2, name: "Housing")
        ]
        let vm = CategoryViewModel(apiClient: client)
        await vm.load()

        vm.selectedCategoryId = 2
        XCTAssertEqual(vm.selectedCategory?.name, "Housing")
    }

    // MARK: - createCategory

    func testCreateCategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        client.categoryResult = makeCategoryResponse(id: 3, name: "Entertainment")
        client.categoriesResult = [makeCategory(id: 3, name: "Entertainment")]

        let vm = CategoryViewModel(apiClient: client)
        await vm.createCategory(name: "Entertainment", emoji: "🎬", color: "#007AFF")

        XCTAssertEqual(client.callLog, ["createCategory", "listCategories"])
        XCTAssertEqual(vm.categories.map(\.id), [3])
        XCTAssertNil(vm.error)
    }

    func testCreateCategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.validationError("Name required")

        let vm = CategoryViewModel(apiClient: client)
        await vm.createCategory(name: "", emoji: nil, color: nil)

        guard case .validationError(let msg)? = vm.error else {
            return XCTFail("Expected validationError, got \(String(describing: vm.error))")
        }
        XCTAssertEqual(msg, "Name required")
    }

    // MARK: - updateCategory

    func testUpdateCategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        client.updateCategoryResult = makeCategoryResponse(id: 1, name: "Food & Drink")
        client.categoriesResult = [makeCategory(id: 1, name: "Food & Drink")]

        let vm = CategoryViewModel(apiClient: client)
        await vm.updateCategory(id: 1, name: "Food & Drink", emoji: nil, color: nil)

        XCTAssertEqual(client.callLog, ["updateCategory", "listCategories"])
        XCTAssertEqual(vm.categories.first?.name, "Food & Drink")
        XCTAssertNil(vm.error)
    }

    func testUpdateCategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.notFound

        let vm = CategoryViewModel(apiClient: client)
        await vm.updateCategory(id: 99, name: "Ghost", emoji: nil, color: nil)

        guard case .notFound? = vm.error else {
            return XCTFail("Expected notFound, got \(String(describing: vm.error))")
        }
    }

    // MARK: - deleteCategory

    func testDeleteCategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        client.categoriesResult = []

        let vm = CategoryViewModel(apiClient: client)
        vm.selectedCategoryId = 1
        await vm.deleteCategory(id: 1, replacementCategoryId: nil, replacementSubcategoryId: nil)

        XCTAssertEqual(client.callLog, ["deleteCategory", "listCategories"])
        XCTAssertNil(vm.selectedCategoryId)
        XCTAssertNil(vm.error)
    }

    func testDeleteCategoryWithReplacementPassesIds() async {
        let client = MockAPIClient()
        client.categoriesResult = []

        let vm = CategoryViewModel(apiClient: client)
        await vm.deleteCategory(id: 1, replacementCategoryId: 2, replacementSubcategoryId: 5)

        XCTAssertEqual(client.callLog, ["deleteCategory", "listCategories"])
    }

    func testDeleteCategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Cannot delete system category")

        let vm = CategoryViewModel(apiClient: client)
        await vm.deleteCategory(id: 1, replacementCategoryId: nil, replacementSubcategoryId: nil)

        guard case .serverError(let msg)? = vm.error else {
            return XCTFail("Expected serverError, got \(String(describing: vm.error))")
        }
        XCTAssertEqual(msg, "Cannot delete system category")
    }

    // MARK: - createSubcategory

    func testCreateSubcategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        let sub = makeSubcategory(id: 10, categoryId: 1, name: "Groceries")
        client.createSubcategoryResult = sub
        client.categoriesResult = [makeCategory(id: 1, name: "Food", subcategories: [sub])]

        let vm = CategoryViewModel(apiClient: client)
        await vm.createSubcategory(categoryId: 1, name: "Groceries")

        XCTAssertEqual(client.callLog, ["createSubcategory", "listCategories"])
        XCTAssertEqual(vm.categories.first?.subcategories.first?.name, "Groceries")
        XCTAssertNil(vm.error)
    }

    func testCreateSubcategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.validationError("Name too long")

        let vm = CategoryViewModel(apiClient: client)
        await vm.createSubcategory(categoryId: 1, name: "X".padding(toLength: 300, withPad: "X", startingAt: 0))

        guard case .validationError(let msg)? = vm.error else {
            return XCTFail("Expected validationError, got \(String(describing: vm.error))")
        }
        XCTAssertEqual(msg, "Name too long")
    }

    // MARK: - updateSubcategory

    func testUpdateSubcategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        let updatedSub = makeSubcategory(id: 10, categoryId: 1, name: "Dining Out")
        client.updateSubcategoryResult = updatedSub
        client.categoriesResult = [makeCategory(id: 1, name: "Food", subcategories: [updatedSub])]

        let vm = CategoryViewModel(apiClient: client)
        await vm.updateSubcategory(id: 10, name: "Dining Out")

        XCTAssertEqual(client.callLog, ["updateSubcategory", "listCategories"])
        XCTAssertEqual(vm.categories.first?.subcategories.first?.name, "Dining Out")
        XCTAssertNil(vm.error)
    }

    func testUpdateSubcategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.notFound

        let vm = CategoryViewModel(apiClient: client)
        await vm.updateSubcategory(id: 999, name: "Ghost")

        guard case .notFound? = vm.error else {
            return XCTFail("Expected notFound, got \(String(describing: vm.error))")
        }
    }

    // MARK: - deleteSubcategory

    func testDeleteSubcategoryCallsAPIAndReloads() async {
        let client = MockAPIClient()
        client.categoriesResult = [makeCategory(id: 1, name: "Food")]

        let vm = CategoryViewModel(apiClient: client)
        await vm.deleteSubcategory(id: 10, replacementCategoryId: nil, replacementSubcategoryId: nil)

        XCTAssertEqual(client.callLog, ["deleteSubcategory", "listCategories"])
        XCTAssertNil(vm.error)
    }

    func testDeleteSubcategoryWithReplacementPassesIds() async {
        let client = MockAPIClient()
        client.categoriesResult = []

        let vm = CategoryViewModel(apiClient: client)
        await vm.deleteSubcategory(id: 10, replacementCategoryId: 2, replacementSubcategoryId: 20)

        XCTAssertEqual(client.callLog, ["deleteSubcategory", "listCategories"])
    }

    func testDeleteSubcategoryStoresErrorOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Subcategory in use")

        let vm = CategoryViewModel(apiClient: client)
        await vm.deleteSubcategory(id: 10, replacementCategoryId: nil, replacementSubcategoryId: nil)

        guard case .serverError(let msg)? = vm.error else {
            return XCTFail("Expected serverError, got \(String(describing: vm.error))")
        }
        XCTAssertEqual(msg, "Subcategory in use")
    }
}
