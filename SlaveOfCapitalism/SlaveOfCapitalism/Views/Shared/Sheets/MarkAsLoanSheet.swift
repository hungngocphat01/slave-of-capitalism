import SwiftUI

struct MarkAsLoanSheet: View {
    private let apiClient: any APIClientProtocol
    private let transaction: TransactionWithDetails
    private let isDebt: Bool
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var counterpartyName = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        transaction: TransactionWithDetails,
        isDebt: Bool = false,
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.transaction = transaction
        self.isDebt = isDebt
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

                Section(isDebt ? "Debt Details" : "Loan Details") {
                    TextField(
                        isDebt ? "Who did you borrow from?" : "Who did you lend to?",
                        text: $counterpartyName
                    )

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isDebt ? "Mark as Debt" : "Mark as Loan")
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
        .frame(minWidth: 420, minHeight: 280)
    }

    private var validationMessage: String? {
        if counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Counterparty is required."
        }

        return nil
    }

    private func submit() async {
        guard validationMessage == nil else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let name = counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let notesValue = optionalTrimmedValue(notes)

            if isDebt {
                _ = try await apiClient.markAsDebt(
                    id: transaction.id,
                    MarkAsDebtRequest(counterpartyName: name, notes: notesValue)
                )
            } else {
                _ = try await apiClient.markAsLoan(
                    id: transaction.id,
                    MarkAsLoanRequest(counterpartyName: name, notes: notesValue)
                )
            }

            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optionalTrimmedValue(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
