import SwiftUI

struct MarkAsInstallmentSheet: View {
    private let apiClient: any APIClientProtocol
    private let transaction: TransactionWithDetails
    private let onComplete: () async -> Void

    @Environment(WalletStore.self) private var walletStore
    @Environment(\.dismiss) private var dismiss

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
                    LabeledContent("Wallet", value: counterpartyName)
                }

                Section("Installment Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Mark as Installment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var counterpartyName: String {
        transaction.walletName
            ?? walletStore.wallet(for: transaction.walletId)?.name
            ?? "Installment"
    }

    private func submit() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await apiClient.markAsInstallment(
                id: transaction.id,
                MarkAsLoanRequest(
                    counterpartyName: counterpartyName,
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

    private func optionalTrimmedValue(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
