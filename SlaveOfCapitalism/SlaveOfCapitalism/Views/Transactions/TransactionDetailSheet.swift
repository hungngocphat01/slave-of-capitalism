import SwiftUI

enum TransactionDetailSheetPresentation {
    static func locksStructureEditing(for transaction: TransactionWithDetails) -> Bool {
        transaction.hasLinkedEntry || transaction.isLinkedToEntry
    }

    static func bannerMessage(
        validationMessage: String?,
        errorMessage: String?,
        isEditing: Bool
    ) -> String? {
        if let errorMessage {
            return errorMessage
        }

        if isEditing, let validationMessage {
            return validationMessage
        }

        return nil
    }

    static func structureEditingNote(for transaction: TransactionWithDetails) -> String? {
        guard locksStructureEditing(for: transaction) else { return nil }

        if transaction.isLinkedToEntry {
            return "Direction and classification are fixed by the linked entry this transaction resolves."
        }

        return "Direction and classification are managed by the linked entry workflow for this transaction."
    }
}

struct TransactionDetailSheet: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    private let transaction: TransactionWithDetails
    private let wallets: [WalletWithBalance]
    private let categories: [CategoryWithSubcategories]
    private let onComplete: () async -> Void

    @State private var isEditing = false
    @State private var transactionDate: Date
    @State private var includesTime: Bool
    @State private var transactionTime: Date
    @State private var selectedWalletId: Int
    @State private var direction: TransactionDirection
    @State private var amountText: String
    @State private var classification: TransactionClassification
    @State private var descriptionText: String
    @State private var selectedCategoryId: Int
    @State private var selectedSubcategoryId: Int
    @State private var isIgnored: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        transaction: TransactionWithDetails,
        wallets: [WalletWithBalance],
        categories: [CategoryWithSubcategories],
        onComplete: @escaping () async -> Void
    ) {
        self.transaction = transaction
        self.wallets = wallets
        self.categories = categories
        self.onComplete = onComplete

        let parsedDate = Self.date(from: transaction.date) ?? .now
        let parsedTime = Self.time(from: transaction.time) ?? parsedDate

        _transactionDate = State(initialValue: parsedDate)
        _includesTime = State(initialValue: transaction.time != nil)
        _transactionTime = State(initialValue: parsedTime)
        _selectedWalletId = State(initialValue: transaction.walletId)
        _direction = State(initialValue: transaction.direction)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _classification = State(initialValue: transaction.classification)
        _descriptionText = State(initialValue: transaction.description ?? "")
        _selectedCategoryId = State(initialValue: transaction.categoryId ?? 0)
        _selectedSubcategoryId = State(initialValue: transaction.subcategoryId ?? 0)
        _isIgnored = State(initialValue: transaction.isIgnored)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let bannerMessage {
                    Section {
                        TransactionSheetMessageBanner(
                            tone: errorMessage == nil ? .advisory : .critical,
                            message: bannerMessage
                        )
                    }
                }

                Section("Cash flow") {
                    if isEditing {
                        Picker("Wallet", selection: $selectedWalletId) {
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet.id)
                            }
                        }
                    } else {
                        LabeledContent("Wallet", value: walletName)
                    }
                    
                    LabeledContent("Direction", value: Self.classificationLabel(transaction.direction))
                    LabeledContent("Classification", value: Self.classificationLabel(transaction.classification))
                }

                Section("Basics") {
                    if isEditing {
                        CurrencyField(title: "Amount", text: $amountText)
                        TextField("Description", text: $descriptionText)
                        DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                        Toggle("Include time", isOn: $includesTime)
                        if includesTime {
                            DatePicker("Time", selection: $transactionTime, displayedComponents: .hourAndMinute)
                        }
                    } else {
                        LabeledContent("Amount", value: Formatters.currency(transaction.amount))
                        LabeledContent("Description", value: descriptionValue)
                        LabeledContent("Date", value: transaction.date)
                        if let time = transaction.time {
                            LabeledContent("Time", value: time)
                        }

                        LabeledContent("Category", value: categoryName)
                    }
                }
                
                if isEditing {
                    Section("Category") {
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("None").tag(0)
                            ForEach(categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }

                        Picker("Subcategory", selection: $selectedSubcategoryId) {
                            Text("None").tag(0)
                            ForEach(activeSubcategories) { subcategory in
                                Text(subcategory.name).tag(subcategory.id)
                            }
                        }
                        .disabled(activeSubcategories.isEmpty)
                    }
                }

                if let linkedEntry = transaction.linkedEntry {
                    Section("Linked Entry") {
                        LabeledContent("Counterparty", value: linkedEntry.counterpartyName)
                        LabeledContent("Type", value: linkedEntry.linkType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        LabeledContent("Status", value: linkedEntry.status.rawValue.capitalized)
                        LabeledContent("Total Amount", value: Formatters.currency(linkedEntry.totalAmount))
                        if let userAmount = linkedEntry.userAmount {
                            LabeledContent("Your Share", value: Formatters.currency(userAmount))
                        }
                        LabeledContent("Pending", value: Formatters.currency(linkedEntry.pendingAmount))
                        if let notes = linkedEntry.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section("Status") {
                    if isEditing {
                        Toggle("Ignored", isOn: $isIgnored)
                    } else {
                        LabeledContent("Ignored", value: transaction.isIgnored ? "Yes" : "No")
                    }
                    LabeledContent("Calibration", value: transaction.isCalibration ? "Yes" : "No")
                    LabeledContent("Transaction ID", value: String(transaction.id))
                    LabeledContent("Created", value: transaction.createdAt)
                    LabeledContent("Updated", value: transaction.updatedAt)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Transaction" : "Transaction Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Close") {
                        if isEditing {
                            resetDraft()
                            isEditing = false
                            dismiss()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .primaryAction) {
                    if !isEditing {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }

                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await save()
                            }
                        }
                        .disabled(isSaving || validationMessage != nil)
                    }
                }
            }
            .onChange(of: selectedCategoryId) { _, newValue in
                if !activeSubcategories.contains(where: { $0.id == selectedSubcategoryId && $0.categoryId == newValue }) {
                    selectedSubcategoryId = 0
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private var activeSubcategories: [SubcategoryResponse] {
        categories.first(where: { $0.id == selectedCategoryId })?.subcategories ?? []
    }

    private var walletName: String {
        transaction.walletName ?? wallets.first(where: { $0.id == transaction.walletId })?.name ?? "Unknown"
    }

    private var categoryName: String {
        if let subcategoryName = transaction.subcategoryName {
            return subcategoryName
        }
        if let categoryName = transaction.categoryName {
            return categoryName
        }
        return "Uncategorized"
    }

    private var descriptionValue: String {
        let trimmedDescription = (transaction.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDescription.isEmpty ? "Untitled Transaction" : trimmedDescription
    }

    private var bannerMessage: String? {
        TransactionDetailSheetPresentation.bannerMessage(
            validationMessage: validationMessage,
            errorMessage: errorMessage,
            isEditing: isEditing
        )
    }

    private var structureEditingIsLocked: Bool {
        TransactionDetailSheetPresentation.locksStructureEditing(for: transaction)
    }

    private var structureEditingNote: String? {
        TransactionDetailSheetPresentation.structureEditingNote(for: transaction)
    }

    private var validationMessage: String? {
        guard selectedWalletId != 0 else {
            return "Select a wallet."
        }

        guard let amount = decimalValue(from: amountText), amount > 0 else {
            return "Enter an amount greater than zero."
        }

        guard !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Description is required."
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
            let request = TransactionUpdate(
                date: Self.isoDateString(from: transactionDate),
                time: includesTime ? Self.isoTimeString(from: transactionTime) : nil,
                walletId: selectedWalletId,
                direction: direction,
                amount: amount,
                classification: classification,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
                subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId,
                isIgnored: isIgnored,
                isCalibration: transaction.isCalibration,
                allowLargeCacheRebuild: nil
            )
            _ = try await apiClient.updateTransaction(id: transaction.id, request)
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

    private func resetDraft() {
        let parsedDate = Self.date(from: transaction.date) ?? .now
        let parsedTime = Self.time(from: transaction.time) ?? parsedDate

        transactionDate = parsedDate
        includesTime = transaction.time != nil
        transactionTime = parsedTime
        selectedWalletId = transaction.walletId
        direction = transaction.direction
        amountText = NSDecimalNumber(decimal: transaction.amount).stringValue
        classification = transaction.classification
        descriptionText = transaction.description ?? ""
        selectedCategoryId = transaction.categoryId ?? 0
        selectedSubcategoryId = transaction.subcategoryId ?? 0
        isIgnored = transaction.isIgnored
        errorMessage = nil
    }

    private static func classificationLabel(_ value: some RawRepresentable<String>) -> String {
        value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private static func time(from string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = string.count == 5 ? "HH:mm" : "HH:mm:ss"
        return formatter.date(from: string)
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
