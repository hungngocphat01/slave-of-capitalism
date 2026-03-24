import SwiftUI

struct TransactionSheetMessageBanner: View {
    enum Tone {
        case advisory
        case critical

        var iconName: String {
            switch self {
            case .advisory:
                return "exclamationmark.circle.fill"
            case .critical:
                return "xmark.octagon.fill"
            }
        }

        var title: String {
            switch self {
            case .advisory:
                return "Complete Required Fields"
            case .critical:
                return "Couldn't Save Transaction"
            }
        }

        var tint: Color {
            switch self {
            case .advisory:
                return .orange
            case .critical:
                return .red
            }
        }
    }

    let tone: Tone
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tone.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(tone.title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

enum AddTransactionSheetPresentation {
    struct Banner {
        let tone: TransactionSheetMessageBanner.Tone
        let message: String
    }

    static func banner(validationMessage: String?, errorMessage: String?) -> Banner? {
        if let errorMessage {
            return Banner(tone: .critical, message: errorMessage)
        }

        if let validationMessage {
            return Banner(tone: .advisory, message: validationMessage)
        }

        return nil
    }
}

struct TransactionCategoryMenuModel {
    private static let subcategoryIndent = "    "

    struct MenuSection: Identifiable, Equatable {
        let categoryId: Int
        let headerTitle: String?
        let rows: [MenuRow]

        var id: Int {
            categoryId
        }
    }

    struct MenuRow: Identifiable, Equatable {
        let id: String
        let title: String
    }

    static func sections(from categories: [CategoryWithSubcategories]) -> [MenuSection] {
        categories.map { category in
            if category.subcategories.isEmpty {
                return MenuSection(
                    categoryId: category.id,
                    headerTitle: nil,
                    rows: [
                        MenuRow(
                            id: "c:\(category.id)",
                            title: displayTitle(for: category)
                        )
                    ]
                )
            }

            return MenuSection(
                categoryId: category.id,
                headerTitle: displayTitle(for: category),
                rows: category.subcategories.map { subcategory in
                    MenuRow(
                        id: "s:\(subcategory.id)",
                        title: subcategoryIndent + subcategory.name
                    )
                }
            )
        }
    }

    static func optionId(
        categoryId: Int?,
        subcategoryId: Int?,
        categories: [CategoryWithSubcategories]
    ) -> String {
        if let subcategoryId {
            return "s:\(subcategoryId)"
        }

        if let categoryId,
           let category = categories.first(where: { $0.id == categoryId }),
           category.subcategories.isEmpty {
            return "c:\(categoryId)"
        }

        return "u:0"
    }

    static func isValid(optionId: String, categories: [CategoryWithSubcategories]) -> Bool {
        if optionId == "u:0" {
            return true
        }

        if let categoryId = categoryId(from: optionId) {
            return categories.first(where: { $0.id == categoryId })?.subcategories.isEmpty == true
        }

        if let subcategoryId = subcategoryId(from: optionId) {
            return categories.contains(where: { $0.subcategories.contains(where: { $0.id == subcategoryId }) })
        }

        return false
    }

    static func selectionTitle(
        categoryId: Int?,
        subcategoryId: Int?,
        categories: [CategoryWithSubcategories]
    ) -> String {
        if let subcategoryId {
            for category in categories {
                if let subcategory = category.subcategories.first(where: { $0.id == subcategoryId }) {
                    return subcategory.name
                }
            }
        }

        if let categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            return displayTitle(for: category)
        }

        return "Uncategorized"
    }

    static func displayTitle(for category: CategoryWithSubcategories) -> String {
        if let emoji = category.emoji?.trimmingCharacters(in: .whitespacesAndNewlines),
           !emoji.isEmpty {
            return "\(emoji) \(category.name)"
        }
        return category.name
    }

    private static func categoryId(from optionId: String) -> Int? {
        guard optionId.hasPrefix("c:") else { return nil }
        return Int(optionId.dropFirst(2))
    }

    private static func subcategoryId(from optionId: String) -> Int? {
        guard optionId.hasPrefix("s:") else { return nil }
        return Int(optionId.dropFirst(2))
    }
}

struct AddTransactionSheet: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    private let wallets: [WalletWithBalance]
    private let categories: [CategoryWithSubcategories]
    private let onComplete: () async -> Void

    @State private var transactionDate = Date.now
    @State private var includesTime = false
    @State private var transactionTime = Date.now
    @State private var selectedWalletId: Int
    @State private var selectedTransactionType: TransactionType = .expense
    @State private var amountText = "0"
    @State private var descriptionText = ""
    @State private var selectedCategoryId: Int = 0
    @State private var selectedSubcategoryId: Int = 0
    @State private var selectedCategoryOptionId: String = "u:0"
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        wallets: [WalletWithBalance],
        categories: [CategoryWithSubcategories],
        onComplete: @escaping () async -> Void
    ) {
        self.wallets = wallets
        self.categories = categories
        self.onComplete = onComplete
        _selectedWalletId = State(initialValue: wallets.first?.id ?? 0)
        _selectedCategoryOptionId = State(initialValue: "u:0")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let banner = AddTransactionSheetPresentation.banner(
                    validationMessage: validationMessage,
                    errorMessage: errorMessage
                ) {
                    Section {
                        TransactionSheetMessageBanner(
                            tone: banner.tone,
                            message: banner.message
                        )
                    }
                }

                Section("When") {
                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                    Toggle("Include time", isOn: $includesTime)
                    if includesTime {
                        DatePicker("Time", selection: $transactionTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Basics") {
                    if wallets.isEmpty {
                        Text("Create a wallet before adding transactions.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Wallet", selection: $selectedWalletId) {
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet.id)
                            }
                        }
                    }

                    Picker("Type", selection: $selectedTransactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Amount") {
                        CurrencyField(title: "Amount", text: $amountText, prompt: "0")
                            .frame(width: 120)
                    }
                    TextField("Description", text: $descriptionText)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryOptionId) {
                        Text("None")
                            .tag("u:0")

                        ForEach(TransactionCategoryMenuModel.sections(from: categories)) { section in
                            if let headerTitle = section.headerTitle {
                                Section(header: Text(verbatim: headerTitle)) {
                                    ForEach(section.rows) { row in
                                        Text(verbatim: row.title)
                                            .tag(row.id)
                                    }
                                }
                            } else {
                                ForEach(section.rows) { row in
                                    Text(verbatim: row.title)
                                        .tag(row.id)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving || validationMessage != nil)
                }
            }
            .onAppear {
                syncCategorySelection()
            }
            .onChange(of: selectedCategoryOptionId) { _, newValue in
                applyCategorySelection(for: newValue)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private var validationMessage: String? {
        guard !wallets.isEmpty else {
            return "A wallet is required."
        }

        guard selectedWalletId != 0 else {
            return "Select a wallet."
        }

        guard let amount = decimalValue(from: amountText), amount > 0 else {
            return "Enter an amount greater than zero."
        }

        guard !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Description is required."
        }

        guard TransactionCategoryMenuModel.isValid(optionId: selectedCategoryOptionId, categories: categories) else {
            return "Select a valid category."
        }

        return nil
    }

    private func save() async {
        guard validationMessage == nil, let amount = decimalValue(from: amountText) else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let request = TransactionCreate(
                date: Self.isoDateString(from: transactionDate),
                time: includesTime ? Self.isoTimeString(from: transactionTime) : nil,
                walletId: selectedWalletId,
                direction: selectedTransactionType.direction,
                amount: amount,
                classification: selectedTransactionType.classification,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
                subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId
            )
            _ = try await apiClient.createTransaction(request)
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimalValue(from text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func applyCategorySelection(for optionId: String) {
        if optionId == "u:0" {
            selectedCategoryId = 0
            selectedSubcategoryId = 0
            return
        }

        if let categoryId = Self.categoryId(from: optionId),
           let category = categories.first(where: { $0.id == categoryId }),
           category.subcategories.isEmpty {
            selectedCategoryId = categoryId
            selectedSubcategoryId = 0
            return
        }

        if let subcategoryId = Self.subcategoryId(from: optionId),
           let category = categories.first(where: { $0.subcategories.contains(where: { $0.id == subcategoryId }) }),
           category.subcategories.contains(where: { $0.id == subcategoryId }) {
            selectedCategoryId = category.id
            selectedSubcategoryId = subcategoryId
            return
        }

        selectedCategoryOptionId = Self.optionId(categoryId: selectedCategoryId, subcategoryId: selectedSubcategoryId, categories: categories)
    }

    private func syncCategorySelection() {
        selectedCategoryOptionId = Self.optionId(
            categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
            subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId,
            categories: categories
        )
    }

    private static func optionId(categoryId: Int?, subcategoryId: Int?, categories: [CategoryWithSubcategories]) -> String {
        TransactionCategoryMenuModel.optionId(
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            categories: categories
        )
    }

    private static func categoryId(from optionId: String) -> Int? {
        if optionId == "u:0" {
            return nil
        }

        guard optionId.hasPrefix("c:") else { return nil }
        return Int(optionId.dropFirst(2))
    }

    private static func subcategoryId(from optionId: String) -> Int? {
        guard optionId.hasPrefix("s:") else { return nil }
        return Int(optionId.dropFirst(2))
    }

    private static func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private enum TransactionType: String, CaseIterable, Sendable {
    case expense
    case income

    var direction: TransactionDirection {
        switch self {
        case .expense:
            return .outflow
        case .income:
            return .inflow
        }
    }

    var classification: TransactionClassification {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        }
    }

    var label: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        }
    }
}
