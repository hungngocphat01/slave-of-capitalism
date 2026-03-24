import SwiftUI

struct EditableCategoryPickerSelectionState: Equatable {
    let selectedOptionId: String
    let initialOptionId: String

    static func make(
        categoryId: Int?,
        subcategoryId: Int?,
        categories: [CategoryWithSubcategories]
    ) -> EditableCategoryPickerSelectionState {
        let optionId = optionId(
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            categories: categories
        )
        return EditableCategoryPickerSelectionState(
            selectedOptionId: optionId,
            initialOptionId: optionId
        )
    }

    static func optionId(
        categoryId: Int?,
        subcategoryId: Int?,
        categories: [CategoryWithSubcategories]
    ) -> String {
        if let subcategoryId {
            return "s:\(subcategoryId)"
        }

        if let categoryId {
            if let category = categories.first(where: { $0.id == categoryId }), !category.subcategories.isEmpty {
                return "h:\(category.id)"
            }
            return TransactionCategoryMenuModel.optionId(
                categoryId: categoryId,
                subcategoryId: nil,
                categories: categories
            )
        }

        return "u:0"
    }
}

struct EditableCategoryPicker: View {
    let displayText: String
    let isEditing: Bool
    let isUncategorized: Bool
    let categories: [CategoryWithSubcategories]
    @Binding var selectedCategoryId: Int
    @Binding var selectedSubcategoryId: Int
    let onBeginEdit: () -> Void
    let onCommit: (Int?, Int?) -> Void
    let onCancel: () -> Void

    @State private var selectedOptionId: String = "u:0"
    @State private var initialOptionId: String = "u:0"

    private var menuSections: [TransactionCategoryMenuModel.MenuSection] {
        TransactionCategoryMenuModel.sections(from: categories)
    }

    private var currentSelectionTitle: String {
        TransactionCategoryMenuModel.selectionTitle(
            categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
            subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId,
            categories: categories
        )
    }

    private func currentSelectionState() -> EditableCategoryPickerSelectionState {
        let state = EditableCategoryPickerSelectionState.make(
            categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
            subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId,
            categories: categories
        )

        return state
    }

    private func syncSelectionIfNeeded() {
        selectedOptionId = currentSelectionState().selectedOptionId
    }

    private func resetSelectionState() {
        let state = currentSelectionState()
        selectedOptionId = state.selectedOptionId
        initialOptionId = state.initialOptionId
    }

    private func commitSelectionIfNeeded(optionId: String) {
        guard optionId != initialOptionId else { return }

        selectedOptionId = optionId

        if optionId == "u:0" {
            onCommit(nil, nil)
            return
        }

        if let categoryId = categoryId(from: optionId) {
            onCommit(categoryId, nil)
            return
        }

        guard let subcategoryId = subcategoryId(from: optionId) else { return }

        for category in categories {
            if category.subcategories.contains(where: { $0.id == subcategoryId }) {
                onCommit(category.id, subcategoryId)
                return
            }
        }
    }

    private func categoryId(from optionId: String) -> Int? {
        guard optionId.hasPrefix("c:") else { return nil }
        return Int(optionId.dropFirst(2))
    }

    private func subcategoryId(from optionId: String) -> Int? {
        guard optionId.hasPrefix("s:") else { return nil }
        return Int(optionId.dropFirst(2))
    }

    private func menuItemTitle(_ title: String, optionId: String) -> String {
        selectedOptionId == optionId ? "✓ \(title)" : title
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 6) {
                    Menu {
                        Button {
                            commitSelectionIfNeeded(optionId: "u:0")
                        } label: {
                            Text(verbatim: menuItemTitle("Uncategorized", optionId: "u:0"))
                        }

                        ForEach(menuSections) { section in
                            if let headerTitle = section.headerTitle {
                                Section(header: Text(verbatim: headerTitle)) {
                                    ForEach(section.rows) { row in
                                        Button {
                                            commitSelectionIfNeeded(optionId: row.id)
                                        } label: {
                                            Text(verbatim: menuItemTitle(row.title, optionId: row.id))
                                        }
                                    }
                                }
                            } else {
                                ForEach(section.rows) { row in
                                    Button {
                                        commitSelectionIfNeeded(optionId: row.id)
                                    } label: {
                                        Text(verbatim: menuItemTitle(row.title, optionId: row.id))
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentSelectionTitle)
                                .foregroundStyle(isUncategorized ? .secondary : .primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .onExitCommand {
                    onCancel()
                }
                .onAppear {
                    resetSelectionState()
                }
                .onChange(of: selectedCategoryId) { _, _ in
                    syncSelectionIfNeeded()
                }
                .onChange(of: selectedSubcategoryId) { _, _ in
                    syncSelectionIfNeeded()
                }
            } else {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(isUncategorized ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        onBeginEdit()
                    })
            }
        }
    }
}
