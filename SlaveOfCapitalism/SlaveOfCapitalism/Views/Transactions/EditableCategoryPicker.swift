import SwiftUI

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

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 4) {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Uncategorized").tag(0)
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedCategoryId) { _, _ in
                        selectedSubcategoryId = 0
                    }

                    if let category = categories.first(where: { $0.id == selectedCategoryId }),
                       !category.subcategories.isEmpty {
                        Picker("Sub", selection: $selectedSubcategoryId) {
                            Text("None").tag(0)
                            ForEach(category.subcategories) { sub in
                                Text(sub.name).tag(sub.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Button("OK") {
                        let catId = selectedCategoryId == 0 ? nil : selectedCategoryId
                        let subId = selectedSubcategoryId == 0 ? nil : selectedSubcategoryId
                        onCommit(catId, subId)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .onExitCommand {
                    onCancel()
                }
            } else {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(isUncategorized ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBeginEdit()
                    }
            }
        }
    }
}
