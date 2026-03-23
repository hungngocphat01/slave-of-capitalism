import SwiftUI

struct ReclassifySheet: View {
    private let apiClient: any APIClientProtocol
    private let transaction: TransactionWithDetails
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedClassification: TransactionClassification
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
        _selectedClassification = State(initialValue: transaction.classification)
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
                    LabeledContent("Current Type", value: label(for: transaction.classification))
                    LabeledContent("Direction", value: transaction.direction.rawValue.capitalized)
                }

                Section("New Classification") {
                    Picker("Type", selection: $selectedClassification) {
                        ForEach(options, id: \.self) { option in
                            Text(label(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reclassify Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .disabled(isSaving || selectedClassification == transaction.classification)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }

    private var options: [TransactionClassification] {
        switch transaction.direction {
        case .outflow:
            return [.expense, .transfer, .loanRepayment, .installmtChrge]
        case .inflow:
            return [.income, .transfer, .borrow, .debtCollection]
        case .reserved:
            return [.expense, .income, .transfer]
        }
    }

    private func submit() async {
        guard selectedClassification != transaction.classification else {
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await apiClient.reclassifyTransaction(
                id: transaction.id,
                ReclassifyRequest(classification: selectedClassification)
            )
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func label(for value: TransactionClassification) -> String {
        value.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
