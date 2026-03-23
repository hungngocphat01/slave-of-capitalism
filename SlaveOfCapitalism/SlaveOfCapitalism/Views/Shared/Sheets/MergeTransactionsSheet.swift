import SwiftUI

struct MergeTransactionsSheet: View {
    private let apiClient: any APIClientProtocol
    private let transactions: [TransactionWithDetails]
    private let categories: [CategoryWithSubcategories]
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mergedDate = Date.now
    @State private var descriptionText: String
    @State private var selectedCategoryId: Int
    @State private var selectedSubcategoryId: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        transactions: [TransactionWithDetails],
        categories: [CategoryWithSubcategories],
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.transactions = transactions
        self.categories = categories
        self.onComplete = onComplete

        _descriptionText = State(initialValue: transactions.first?.description ?? "Merged transaction")
        _selectedCategoryId = State(initialValue: transactions.first?.categoryId ?? 0)
        _selectedSubcategoryId = State(initialValue: transactions.first?.subcategoryId ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Section("Selection") {
                    LabeledContent("Transactions", value: "\(transactions.count)")
                    LabeledContent("Total Amount", value: Formatters.currency(totalAmount))
                    LabeledContent("Wallet", value: walletName)
                    LabeledContent("Direction", value: directionLabel)
                }

                Section("Merged Transaction") {
                    DatePicker("Date", selection: $mergedDate, displayedComponents: .date)
                    TextField("Description", text: $descriptionText)
                }

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

                Section("Items") {
                    ForEach(transactions) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transaction.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(transaction.description ?? "No description")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(Formatters.currency(transaction.amount))
                                .foregroundStyle(transaction.direction == .inflow ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Merge Transactions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        Task { await submit() }
                    }
                    .disabled(isSaving || validationMessage != nil)
                }
            }
            .onChange(of: selectedCategoryId) { _, newValue in
                if !activeSubcategories.contains(where: { $0.id == selectedSubcategoryId && $0.categoryId == newValue }) {
                    selectedSubcategoryId = 0
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var totalAmount: Decimal {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private var walletName: String {
        transactions.first?.walletName ?? "Unknown"
    }

    private var directionLabel: String {
        transactions.first?.direction.rawValue.capitalized ?? "Unknown"
    }

    private var activeSubcategories: [SubcategoryResponse] {
        categories.first(where: { $0.id == selectedCategoryId })?.subcategories ?? []
    }

    private var validationMessage: String? {
        if transactions.count < 2 {
            return "Select at least two transactions."
        }

        if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Description is required."
        }

        guard let first = transactions.first else {
            return "No transactions selected."
        }

        let sameWallet = transactions.allSatisfy { $0.walletId == first.walletId }
        if !sameWallet {
            return "All transactions must belong to the same wallet."
        }

        let sameDirection = transactions.allSatisfy { $0.direction == first.direction }
        if !sameDirection {
            return "All transactions must have the same direction."
        }

        let hasUnsupported = transactions.contains { $0.isCalibration || !($0.classification == .expense || $0.classification == .income) }
        if hasUnsupported {
            return "Only non-calibration expense/income transactions can be merged."
        }

        return nil
    }

    private func submit() async {
        guard validationMessage == nil else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let request = TransactionMergeRequest(
                transactionIds: transactions.map(\.id),
                date: isoDateString(from: mergedDate),
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
                subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId
            )

            _ = try await apiClient.mergeTransactions(request)
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
