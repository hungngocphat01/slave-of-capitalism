import SwiftUI

struct ResolveCalibrationSheet: View {
    private enum ResolutionType: String, CaseIterable {
        case expense
        case income

        var title: String { rawValue.capitalized }

        var direction: TransactionDirection {
            switch self {
            case .expense: return .outflow
            case .income: return .inflow
            }
        }

        var classification: TransactionClassification {
            switch self {
            case .expense: return .expense
            case .income: return .income
            }
        }
    }

    private let apiClient: any APIClientProtocol
    private let calibration: TransactionWithDetails
    private let categories: [CategoryWithSubcategories]
    private let wallets: [WalletWithBalance]
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var transactionDate = Date.now
    @State private var resolutionType: ResolutionType
    @State private var amountText: String
    @State private var descriptionText = ""
    @State private var selectedCategoryId = 0
    @State private var selectedSubcategoryId = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        calibration: TransactionWithDetails,
        categories: [CategoryWithSubcategories],
        wallets: [WalletWithBalance],
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.calibration = calibration
        self.categories = categories
        self.wallets = wallets
        self.onComplete = onComplete

        _resolutionType = State(initialValue: calibration.direction == .inflow ? .income : .expense)
        _amountText = State(initialValue: NSDecimalNumber(decimal: calibration.amount).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Section("Calibration") {
                    LabeledContent("Original Amount", value: Formatters.currency(calibration.amount))
                    LabeledContent("Wallet", value: walletName)
                    LabeledContent("Description", value: calibration.description ?? "No description")
                }

                Section("Replacement Transaction") {
                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)

                    Picker("Type", selection: $resolutionType) {
                        ForEach(ResolutionType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
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
            .navigationTitle("Resolve Calibration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Resolve") {
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
        .frame(minWidth: 520, minHeight: 500)
    }

    private var walletName: String {
        calibration.walletName ?? wallets.first(where: { $0.id == calibration.walletId })?.name ?? "Unknown"
    }

    private var activeSubcategories: [SubcategoryResponse] {
        categories.first(where: { $0.id == selectedCategoryId })?.subcategories ?? []
    }

    private var validationMessage: String? {
        guard let amount = decimalValue(from: amountText), amount > 0 else {
            return "Enter an amount greater than zero."
        }

        return nil
    }

    private func submit() async {
        guard validationMessage == nil, let amount = decimalValue(from: amountText) else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let request = ResolveCalibrationRequest(
                date: isoDateString(from: transactionDate),
                time: nil,
                walletId: calibration.walletId,
                direction: resolutionType.direction,
                amount: amount,
                classification: resolutionType.classification,
                description: optionalTrimmed(descriptionText),
                categoryId: selectedCategoryId == 0 ? nil : selectedCategoryId,
                subcategoryId: selectedSubcategoryId == 0 ? nil : selectedSubcategoryId
            )

            _ = try await apiClient.resolveCalibration(id: calibration.id, request)
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimalValue(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func optionalTrimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
