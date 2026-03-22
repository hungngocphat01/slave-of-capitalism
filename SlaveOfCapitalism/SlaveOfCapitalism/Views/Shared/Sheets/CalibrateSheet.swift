import SwiftUI

struct CalibrateSheet: View {
    private let apiClient: any APIClientProtocol
    private let wallet: WalletWithBalance
    private let categories: [CategoryWithSubcategories]
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var correctBalanceText: String
    @State private var selectedCategoryId: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        wallet: WalletWithBalance,
        categories: [CategoryWithSubcategories],
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.wallet = wallet
        self.categories = categories
        self.onComplete = onComplete

        _correctBalanceText = State(initialValue: Self.decimalString(wallet.currentBalance))
        _selectedCategoryId = State(initialValue: Self.defaultCategoryId(from: categories))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Wallet") {
                    Text(wallet.name)
                    LabeledContent("Current balance", value: Formatters.currency(wallet.currentBalance))
                }

                Section("Calibration") {
                    TextField("Correct balance", text: $correctBalanceText)
                    LabeledContent("Difference", value: Formatters.currency(balanceDifference))

                    if categories.isEmpty {
                        Text("Create at least one category before calibrating a wallet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Category", selection: $selectedCategoryId) {
                            ForEach(categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Calibrate Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await submitCalibration()
                        }
                    }
                    .disabled(isSaving || categories.isEmpty || balanceDifference == 0)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var balanceDifference: Decimal {
        (decimalValue(from: correctBalanceText) ?? wallet.currentBalance) - wallet.currentBalance
    }

    private func submitCalibration() async {
        guard let correctBalance = decimalValue(from: correctBalanceText) else {
            errorMessage = "Enter a valid balance."
            return
        }

        guard selectedCategoryId != 0 else {
            errorMessage = "Select a category."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let request = CalibrateWalletRequest(
                correctBalance: correctBalance,
                miscCategoryId: selectedCategoryId
            )
            _ = try await apiClient.calibrateWallet(id: wallet.id, request)
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

    private static func defaultCategoryId(from categories: [CategoryWithSubcategories]) -> Int {
        categories.first(where: { $0.name.localizedCaseInsensitiveContains("misc") })?.id
            ?? categories.first?.id
            ?? 0
    }

    private static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}
