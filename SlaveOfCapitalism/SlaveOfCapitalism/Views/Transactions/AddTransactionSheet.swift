import SwiftUI

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
    @State private var direction: TransactionDirection = .outflow
    @State private var amountText = ""
    @State private var classification: TransactionClassification = .expense
    @State private var descriptionText = ""
    @State private var selectedCategoryId: Int = 0
    @State private var selectedSubcategoryId: Int = 0
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
    }

    var body: some View {
        NavigationStack {
            Form {
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
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

                    Picker("Direction", selection: $direction) {
                        Text("Outflow").tag(TransactionDirection.outflow)
                        Text("Inflow").tag(TransactionDirection.inflow)
                        Text("Reserved").tag(TransactionDirection.reserved)
                    }

                    Picker("Classification", selection: $classification) {
                        ForEach(TransactionClassification.allCases, id: \.self) { option in
                            Text(Self.classificationLabel(option)).tag(option)
                        }
                    }

                    CurrencyField(title: "Amount", text: $amountText, prompt: "0")
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
            .onChange(of: selectedCategoryId) { _, newValue in
                if !activeSubcategories.contains(where: { $0.id == selectedSubcategoryId && $0.categoryId == newValue }) {
                    selectedSubcategoryId = 0
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private var activeSubcategories: [SubcategoryResponse] {
        categories.first(where: { $0.id == selectedCategoryId })?.subcategories ?? []
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
                direction: direction,
                amount: amount,
                classification: classification,
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

    private static func classificationLabel(_ value: TransactionClassification) -> String {
        value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
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
