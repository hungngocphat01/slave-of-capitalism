import SwiftUI

struct ReimbursementsSheet: View {
    private let apiClient: any APIClientProtocol
    private let transaction: TransactionWithDetails

    @Environment(\.dismiss) private var dismiss

    @State private var linkedEntry: LinkedEntryWithDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(apiClient: any APIClientProtocol, transaction: TransactionWithDetails) {
        self.apiClient = apiClient
        self.transaction = transaction
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading reimbursements...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let linkedEntry {
                    Form {
                        Section("Entry") {
                            LabeledContent("Counterparty", value: linkedEntry.counterpartyName)
                            LabeledContent("Type", value: linkedEntry.linkType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            LabeledContent("Status", value: linkedEntry.status.rawValue.capitalized)
                            LabeledContent("Total Amount", value: Formatters.currency(linkedEntry.totalAmount))
                            LabeledContent("Remaining", value: Formatters.currency(linkedEntry.pendingAmount))
                        }

                        Section("Linked Transactions") {
                            if linkedEntry.linkedTransactions.isEmpty {
                                Text("No linked transactions yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(linkedEntry.linkedTransactions) { link in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(link.date ?? "-")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(link.description ?? "No description")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        Text(Formatters.currency(link.amount))
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                } else {
                    ContentUnavailableView {
                        Label("No Reimbursements", systemImage: "tray")
                    } description: {
                        Text(errorMessage ?? "No linked entry found for this transaction.")
                    }
                }
            }
            .navigationTitle("Reimbursements")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true

        isLoading = true
        defer { isLoading = false }

        if let fallbackEntry = fallbackLinkedEntry {
            linkedEntry = fallbackEntry
        }

        do {
            linkedEntry = try await apiClient.getLinkedEntryByTransaction(transactionId: transaction.id)
            errorMessage = nil
        } catch let apiError as APIError {
            switch apiError {
            case .notFound:
                if linkedEntry == nil {
                    errorMessage = "No linked entry found for this transaction."
                }
            default:
                errorMessage = apiError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var fallbackLinkedEntry: LinkedEntryWithDetails? {
        guard let linkedEntry = transaction.linkedEntry else { return nil }

        return LinkedEntryWithDetails(
            id: linkedEntry.id,
            linkType: linkedEntry.linkType,
            primaryTransactionId: linkedEntry.primaryTransactionId,
            counterpartyName: linkedEntry.counterpartyName,
            totalAmount: linkedEntry.totalAmount,
            userAmount: linkedEntry.userAmount,
            pendingAmount: linkedEntry.pendingAmount,
            status: linkedEntry.status,
            notes: linkedEntry.notes,
            createdAt: linkedEntry.createdAt,
            updatedAt: linkedEntry.updatedAt,
            linkedTransactions: linkedEntry.linkedTransactions,
            primaryTransactionDescription: transaction.description,
            primaryTransactionDate: transaction.date,
            settledAmount: linkedEntry.totalAmount - linkedEntry.pendingAmount
        )
    }
}
