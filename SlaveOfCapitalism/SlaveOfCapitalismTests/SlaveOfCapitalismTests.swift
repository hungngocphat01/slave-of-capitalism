import XCTest
@testable import SlaveOfCapitalism

final class SlaveOfCapitalismTests: XCTestCase {
    func testInlineEditStateBeginsEditingAndSelectsTransactionRow() {
        var state = TransactionInlineEditState()

        state.beginTextEdit(transactionId: 42, field: .description, text: "Lunch")

        XCTAssertEqual(state.editingTransactionId, 42)
        XCTAssertEqual(state.editingField, .description)
        XCTAssertEqual(state.selectedRowIds, ["t:42"])
        XCTAssertEqual(state.editText, "Lunch")
    }

    func testInlineEditStateDropsDayHeadersAndCancelsEditingWhenSelectionClears() {
        var state = TransactionInlineEditState()
        state.beginWalletEdit(transactionId: 7, walletId: 3)

        let selection = state.applyTableSelection(["d:2026-03-23"])

        XCTAssertEqual(selection.rowIds, Set<String>())
        XCTAssertEqual(selection.transactionIds, Set<Int>())
        XCTAssertNil(state.editingTransactionId)
        XCTAssertNil(state.editingField)
        XCTAssertNil(state.editWalletInitialId)
    }

    func testInlineEditStateCancelsEditingWhenAnotherTransactionRowIsSelected() {
        var state = TransactionInlineEditState()
        state.beginCategoryEdit(transactionId: 7, categoryId: 4, subcategoryId: 9)

        let selection = state.applyTableSelection(["t:99"])

        XCTAssertEqual(selection.rowIds, ["t:99"])
        XCTAssertEqual(selection.transactionIds, [99])
        XCTAssertNil(state.editingTransactionId)
        XCTAssertNil(state.editingField)
    }

    func testCategoryPickerSelectionStateStartsOnCurrentSubcategoryWithoutPendingCommit() {
        let state = EditableCategoryPickerSelectionState.make(
            categoryId: 1,
            subcategoryId: 11,
            categories: [makeCategory(id: 1, name: "Food", subcategoryIds: [11])]
        )

        XCTAssertEqual(state.selectedOptionId, "s:11")
        XCTAssertEqual(state.initialOptionId, "s:11")
    }

    func testCategoryPickerSelectionStateUsesCategoryHeaderForParentCategoryWithChildren() {
        let state = EditableCategoryPickerSelectionState.make(
            categoryId: 1,
            subcategoryId: nil as Int?,
            categories: [makeCategory(id: 1, name: "Food", subcategoryIds: [11])]
        )

        XCTAssertEqual(state.selectedOptionId, "h:1")
        XCTAssertEqual(state.initialOptionId, "h:1")
    }

    func testTransactionCategoryMenuModelKeepsParentCategoriesAsHeadersOnly() {
        let categories = [
            makeCategory(id: 1, name: "Food", emoji: "🍔", subcategoryIds: [11, 12])
        ]

        let sections = TransactionCategoryMenuModel.sections(from: categories)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].headerTitle, "🍔 Food")
        XCTAssertEqual(sections[0].rows.map(\.id), ["s:11", "s:12"])
        XCTAssertFalse(sections[0].rows.contains(where: { $0.id == "c:1" }))
    }

    func testTransactionCategoryMenuModelRejectsHeaderSelection() {
        let categories = [
            makeCategory(id: 1, name: "Food", emoji: "🍔", subcategoryIds: [11])
        ]

        XCTAssertFalse(TransactionCategoryMenuModel.isValid(optionId: "h:1", categories: categories))
        XCTAssertTrue(TransactionCategoryMenuModel.isValid(optionId: "s:11", categories: categories))
    }

    func testTransactionCategoryMenuModelUsesLeafCategoryRowsForCategoriesWithoutChildren() {
        let categories = [
            makeCategory(id: 2, name: "Coffee", emoji: "☕", subcategoryIds: [])
        ]

        let sections = TransactionCategoryMenuModel.sections(from: categories)

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].headerTitle)
        XCTAssertEqual(sections[0].rows.map(\.title), ["☕ Coffee"])
        XCTAssertEqual(sections[0].rows.map(\.id), ["c:2"])
    }

    private func makeCategory(
        id: Int,
        name: String,
        emoji: String? = nil,
        subcategoryIds: [Int]
    ) -> CategoryWithSubcategories {
        CategoryWithSubcategories(
            id: id,
            name: name,
            emoji: emoji,
            color: nil,
            isSystem: false,
            createdAt: "2026-03-23T00:00:00Z",
            updatedAt: "2026-03-23T00:00:00Z",
            subcategories: subcategoryIds.map { subcategoryId in
                SubcategoryResponse(
                    id: subcategoryId,
                    categoryId: id,
                    name: "Subcategory \(subcategoryId)",
                    isSystem: false,
                    createdAt: "2026-03-23T00:00:00Z",
                    updatedAt: "2026-03-23T00:00:00Z"
                )
            }
        )
    }
}
