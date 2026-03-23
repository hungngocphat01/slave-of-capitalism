import SwiftUI

struct MarkAsSplitSheet: View {
    private let apiClient: any APIClientProtocol
    let transaction: TransactionWithDetails
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var counterpartyName = ""
    @State private var userAmountText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        transaction: TransactionWithDetails,
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.transaction = transaction
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Section("Transaction") {
                    Text(transaction.description ?? "No description")
                    LabeledContent("Amount", value: Formatters.currency(transaction.amount))
                }

                Section("Split Details") {
                    TextField("Counterparty", text: $counterpartyName)
                    CurrencyField(title: "Your Amount", text: $userAmountText)

                    if let userAmount = decimal(from: userAmountText) {
                        let owedAmount = max(Decimal.zero, transaction.amount - userAmount)
                        LabeledContent(
                            counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Other Person Owes"
                                : "\(counterpartyName) Owes",
                            value: Formatters.currency(owedAmount)
                        )
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Mark as Split")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .disabled(isSaving || validationMessage != nil)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var validationMessage: String? {
        if counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Counterparty is required."
        }

        guard let value = decimal(from: userAmountText), value > 0 else {
            return "Enter a valid user amount."
        }

        if value > transaction.amount {
            return "Your amount cannot be greater than total amount."
        }

        return nil
    }

    private func submit() async {
        guard validationMessage == nil, let userAmount = decimal(from: userAmountText) else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await apiClient.markAsSplit(
                id: transaction.id,
                MarkAsSplitRequest(
                    counterpartyName: counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines),
                    userAmount: userAmount,
                    notes: optionalTrimmedValue(notes)
                )
            )
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimal(from text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func optionalTrimmedValue(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
