import SwiftUI

struct ReclassifySheetOption: Identifiable, Equatable {
    let classification: TransactionClassification
    let title: String
    let detail: String

    var id: TransactionClassification { classification }
}

enum ReclassifySheetPresentation {
    static func options(for direction: TransactionDirection) -> [ReclassifySheetOption] {
        classifications(for: direction).map {
            ReclassifySheetOption(
                classification: $0,
                title: title(for: $0),
                detail: detail(for: $0, direction: direction)
            )
        }
    }

    static func title(for classification: TransactionClassification) -> String {
        classification.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func classifications(for direction: TransactionDirection) -> [TransactionClassification] {
        switch direction {
        case .outflow:
            return [.expense, .transfer, .loanRepayment, .installmtChrge]
        case .inflow:
            return [.income, .transfer, .borrow, .debtCollection]
        case .reserved:
            return [.expense, .income, .transfer]
        }
    }

    private static func detail(
        for classification: TransactionClassification,
        direction: TransactionDirection
    ) -> String {
        switch classification {
        case .expense:
            return "Keep this as regular spending."
        case .income:
            return "Treat this inflow as earned or received income."
        case .transfer:
            return "Record it as money moving between your own wallets."
        case .borrow:
            return "Track money you received as borrowed funds."
        case .debtCollection:
            return "Mark money collected against an outstanding debt."
        case .loanRepayment:
            return "Record this payment as settling money you borrowed."
        case .installmtChrge:
            return "Track the outflow as an installment charge."
        case .lend:
            return direction == .outflow
                ? "Track money you gave out as a loan."
                : "Track the transaction as lending activity."
        case .splitPayment:
            return "Use a split flow instead when sharing one transaction."
        case .installment:
            return "Track this transaction as part of an installment plan."
        }
    }
}

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
        SheetDialogScaffold(
            title: "Reclassify Transaction",
            subtitle: "Choose the transaction type that best matches how this money should behave in your records."
        ) {
            if let errorMessage {
                SheetInlineMessage(errorMessage, tone: .error)
            }

            SheetSectionContainer(
                title: "Current Transaction",
                subtitle: "Use the current classification and direction as the reference point for the change."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transaction.description ?? "No description")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            SheetValueLabel("Current Type")
                            Text(label(for: transaction.classification))
                                .fontWeight(.semibold)
                        }

                        GridRow {
                            SheetValueLabel("Direction")
                            Text(transaction.direction.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }

                        GridRow {
                            SheetValueLabel("Amount")
                            Text(Formatters.currency(transaction.amount))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SheetSectionContainer(
                title: "Choose New Type",
                subtitle: "Available options are limited to classifications that match the transaction direction."
            ) {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button {
                            selectedClassification = option.classification
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(option.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 16)

                                Image(systemName: selectedClassification == option.classification ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedClassification == option.classification ? Color.accentColor : Color.secondary.opacity(0.35))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedClassification == option.classification ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } actions: {
            SheetActionBar(
                message: actionMessage,
                isError: errorMessage != nil,
                isWorking: isSaving
            ) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            } primaryAction: {
                Button("Save") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || selectedClassification == transaction.classification)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var options: [ReclassifySheetOption] {
        ReclassifySheetPresentation.options(for: transaction.direction)
    }

    private var actionMessage: String? {
        if let errorMessage {
            return errorMessage
        }

        if selectedClassification == transaction.classification {
            return "Choose a different classification to enable Save."
        }

        return "Current: \(label(for: transaction.classification))  ->  New: \(label(for: selectedClassification))"
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
        ReclassifySheetPresentation.title(for: value)
    }
}
