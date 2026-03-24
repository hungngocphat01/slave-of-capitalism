import SwiftUI

// MARK: - Color Palette

struct CategoryColor: Identifiable, Equatable {
    let id: String
    let hex: String
    let color: Color
    let name: String

    static let palette: [CategoryColor] = [
        CategoryColor(id: "#007AFF", hex: "#007AFF", color: Color(red: 0/255, green: 122/255, blue: 255/255), name: "Blue"),
        CategoryColor(id: "#34C759", hex: "#34C759", color: Color(red: 52/255, green: 199/255, blue: 89/255), name: "Green"),
        CategoryColor(id: "#FFCC00", hex: "#FFCC00", color: Color(red: 255/255, green: 204/255, blue: 0/255), name: "Yellow"),
        CategoryColor(id: "#FF9500", hex: "#FF9500", color: Color(red: 255/255, green: 149/255, blue: 0/255), name: "Orange"),
        CategoryColor(id: "#FF3B30", hex: "#FF3B30", color: Color(red: 255/255, green: 59/255, blue: 48/255), name: "Red"),
        CategoryColor(id: "#AF52DE", hex: "#AF52DE", color: Color(red: 175/255, green: 82/255, blue: 222/255), name: "Purple"),
        CategoryColor(id: "#FF2D55", hex: "#FF2D55", color: Color(red: 255/255, green: 45/255, blue: 85/255), name: "Pink"),
        CategoryColor(id: "#5AC8FA", hex: "#5AC8FA", color: Color(red: 90/255, green: 200/255, blue: 250/255), name: "Teal"),
        CategoryColor(id: "#5856D6", hex: "#5856D6", color: Color(red: 88/255, green: 86/255, blue: 214/255), name: "Indigo"),
        CategoryColor(id: "#A2845E", hex: "#A2845E", color: Color(red: 162/255, green: 132/255, blue: 94/255), name: "Brown"),
    ]

    static func find(hex: String?) -> CategoryColor? {
        guard let hex else { return nil }
        return palette.first { $0.hex.uppercased() == hex.uppercased() }
    }
}

// MARK: - Main View

struct CategoryManagementView: View {
    @Environment(APIClient.self) private var apiClient

    @State private var viewModel: CategoryViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading categories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        initializeViewModelIfNeeded()
                    }
            }
        }
        .navigationTitle("Categories")
    }

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        viewModel = CategoryViewModel(apiClient: apiClient)
    }

    @ViewBuilder
    private func content(for viewModel: CategoryViewModel) -> some View {
        HSplitView {
            CategoryListPane(viewModel: viewModel)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            CategoryEditPane(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: 300)

            SubcategoryPane(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260)
        }
        .task {
            if viewModel.categories.isEmpty && !viewModel.isLoading {
                await viewModel.load()
            }
        }
    }
}

// MARK: - Left Pane: Category List

private struct CategoryListPane: View {
    var viewModel: CategoryViewModel
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.categories.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.categories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.categories, selection: Binding(
                    get: { viewModel.selectedCategoryId },
                    set: { viewModel.selectedCategoryId = $0 }
                )) { category in
                    CategoryRow(category: category)
                        .tag(category.id)
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddSheet) {
            AddCategorySheet(viewModel: viewModel)
        }
    }
}

private struct CategoryRow: View {
    let category: CategoryWithSubcategories

    var body: some View {
        HStack(spacing: 8) {
            if let emoji = category.emoji {
                Text(emoji)
                    .font(.title3)
            } else {
                Circle()
                    .fill(CategoryColor.find(hex: category.color)?.color ?? Color.secondary.opacity(0.3))
                    .frame(width: 22, height: 22)
            }
            Text(category.name)
                .lineLimit(1)
            Spacer()
            if category.isSystem {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Middle Pane: Category Edit

private struct CategoryEditPane: View {
    var viewModel: CategoryViewModel

    @State private var name: String = ""
    @State private var emoji: String = ""
    @State private var selectedColor: CategoryColor? = nil
    @State private var showDeleteConfirmation = false
    @State private var replacementCategoryId: Int? = nil
    @State private var replacementSubcategoryId: Int? = nil

    private var isReadOnly: Bool {
        viewModel.selectedCategory?.isSystem == true
    }

    var body: some View {
        Group {
            if let category = viewModel.selectedCategory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let error = viewModel.error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        if isReadOnly {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                Text("System category — read only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        Group {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Name", systemImage: "tag")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Category name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isReadOnly)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Label("Emoji", systemImage: "face.smiling")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Optional emoji", text: $emoji)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isReadOnly)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Label("Color", systemImage: "paintpalette")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ColorPickerGrid(selected: $selectedColor, disabled: isReadOnly)
                            }
                        }

                        if !isReadOnly {
                            HStack(spacing: 12) {
                                Button("Save") {
                                    Task {
                                        await viewModel.updateCategory(
                                            id: category.id,
                                            name: name.isEmpty ? nil : name,
                                            emoji: emoji.isEmpty ? nil : emoji,
                                            color: selectedColor?.hex
                                        )
                                        syncFields()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                                Spacer()

                                Button("Delete", role: .destructive) {
                                    showDeleteConfirmation = true
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.selectedCategoryId) { _, _ in
                    syncFields()
                }
                .onAppear {
                    syncFields()
                }
                .confirmationDialog(
                    "Delete \"\(category.name)\"?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    // Replacement picker is shown inline below delete button for simplicity
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteCategory(
                                id: category.id,
                                replacementCategoryId: replacementCategoryId,
                                replacementSubcategoryId: replacementSubcategoryId
                            )
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All transactions in this category will be reassigned. This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "No Category Selected",
                    systemImage: "tag",
                    description: Text("Select a category from the list to edit it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func syncFields() {
        guard let cat = viewModel.selectedCategory else { return }
        name = cat.name
        emoji = cat.emoji ?? ""
        selectedColor = CategoryColor.find(hex: cat.color)
    }
}

// MARK: - Color Picker Grid

private struct ColorPickerGrid: View {
    @Binding var selected: CategoryColor?
    var disabled: Bool

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CategoryColor.palette) { categoryColor in
                Button {
                    if !disabled {
                        selected = selected?.id == categoryColor.id ? nil : categoryColor
                    }
                } label: {
                    Circle()
                        .fill(categoryColor.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected?.id == categoryColor.id {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 2)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(selected?.id == categoryColor.id ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(categoryColor.name)
            }
        }
    }
}

// MARK: - Right Pane: Subcategories

private struct SubcategoryPane: View {
    var viewModel: CategoryViewModel

    @State private var newSubcategoryName: String = ""
    @State private var editingSubcategoryId: Int? = nil
    @State private var editingSubcategoryName: String = ""
    @State private var deletingSubcategory: SubcategoryResponse? = nil
    @State private var replacementCategoryId: Int? = nil
    @State private var replacementSubcategoryId: Int? = nil

    var body: some View {
        Group {
            if let category = viewModel.selectedCategory {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Subcategories")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // List
                    if category.subcategories.isEmpty {
                        ContentUnavailableView(
                            "No Subcategories",
                            systemImage: "square.stack",
                            description: Text("Add subcategories below.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(category.subcategories) { subcategory in
                                SubcategoryRow(
                                    subcategory: subcategory,
                                    isEditing: editingSubcategoryId == subcategory.id,
                                    editingName: $editingSubcategoryName,
                                    onEdit: {
                                        editingSubcategoryId = subcategory.id
                                        editingSubcategoryName = subcategory.name
                                    },
                                    onSave: {
                                        let name = editingSubcategoryName
                                        editingSubcategoryId = nil
                                        Task {
                                            await viewModel.updateSubcategory(
                                                id: subcategory.id,
                                                name: name.isEmpty ? nil : name
                                            )
                                        }
                                    },
                                    onCancel: {
                                        editingSubcategoryId = nil
                                    },
                                    onDelete: {
                                        deletingSubcategory = subcategory
                                        replacementCategoryId = nil
                                        replacementSubcategoryId = nil
                                    }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }

                    Divider()

                    // Add subcategory bar
                    if !category.isSystem {
                        HStack(spacing: 8) {
                            TextField("New subcategory", text: $newSubcategoryName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addSubcategory(for: category)
                                }
                            Button {
                                addSubcategory(for: category)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newSubcategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Category Selected",
                    systemImage: "square.stack",
                    description: Text("Select a category to manage its subcategories.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .sheet(item: $deletingSubcategory) { subcategory in
            DeleteSubcategorySheet(
                subcategory: subcategory,
                categories: viewModel.categories,
                onDelete: { repCatId, repSubId in
                    deletingSubcategory = nil
                    Task {
                        await viewModel.deleteSubcategory(
                            id: subcategory.id,
                            replacementCategoryId: repCatId,
                            replacementSubcategoryId: repSubId
                        )
                    }
                },
                onCancel: {
                    deletingSubcategory = nil
                }
            )
        }
    }

    private func addSubcategory(for category: CategoryWithSubcategories) {
        let name = newSubcategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newSubcategoryName = ""
        Task {
            await viewModel.createSubcategory(categoryId: category.id, name: name)
        }
    }
}

private struct SubcategoryRow: View {
    let subcategory: SubcategoryResponse
    let isEditing: Bool
    @Binding var editingName: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onSave() }

                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text(subcategory.name)
                    .lineLimit(1)

                if subcategory.isSystem {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !subcategory.isSystem {
                    HStack(spacing: 4) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Category Sheet

private struct AddCategorySheet: View {
    var viewModel: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var emoji: String = ""
    @State private var selectedColor: CategoryColor? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Category")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Label("Name", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Emoji", systemImage: "face.smiling")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Color", systemImage: "paintpalette")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPickerGrid(selected: $selectedColor, disabled: false)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button("Create") {
                    Task {
                        await viewModel.createCategory(
                            name: name,
                            emoji: emoji.isEmpty ? nil : emoji,
                            color: selectedColor?.hex
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 300)
    }
}

// MARK: - Delete Subcategory Sheet

private struct DeleteSubcategorySheet: View {
    let subcategory: SubcategoryResponse
    let categories: [CategoryWithSubcategories]
    let onDelete: (Int?, Int?) -> Void
    let onCancel: () -> Void

    @State private var selectedCategoryId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil

    private var replacementSubcategories: [SubcategoryResponse] {
        guard let catId = selectedCategoryId,
              let cat = categories.first(where: { $0.id == catId }) else { return [] }
        return cat.subcategories.filter { $0.id != subcategory.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete Subcategory")
                .font(.headline)
            Text("Transactions in \"\(subcategory.name)\" will be reassigned. Choose a replacement or leave blank.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Replacement category (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $selectedCategoryId) {
                    Text("None").tag(Int?.none)
                    ForEach(categories.filter { !$0.isSystem || $0.id != subcategory.categoryId }) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }
                .onChange(of: selectedCategoryId) { _, _ in
                    selectedSubcategoryId = nil
                }

                if selectedCategoryId != nil && !replacementSubcategories.isEmpty {
                    Text("Replacement subcategory (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Subcategory", selection: $selectedSubcategoryId) {
                        Text("None").tag(Int?.none)
                        ForEach(replacementSubcategories) { sub in
                            Text(sub.name).tag(Optional(sub.id))
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    onDelete(selectedCategoryId, selectedSubcategoryId)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 260)
    }
}
