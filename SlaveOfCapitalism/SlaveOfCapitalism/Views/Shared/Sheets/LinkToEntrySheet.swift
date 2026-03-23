import SwiftUI

struct LinkToEntrySheet: View {
    private let apiClient: any APIClientProtocol
    private let transactions: [TransactionWithDetails]
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pendingEntries: [LinkedEntryWithDetails] = []
    @State private var selectedEntryId = 0
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(
        apiClient: any APIClientProtocol,
        transactions: [TransactionWithDetails],
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.transactions = transactions
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading pending entries...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pendingEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Entries", systemImage: "tray")
                    } description: {
                        Text("No pending entries are compatible with the selected transaction direction.")
                    }
                } else {
                    Form {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }

                        Section("Selection") {
                            LabeledContent("Transactions", value: "\(transactions.count)")
                            LabeledContent("Total Amount", value: Formatters.currency(totalAmount))
                        }

                        Section("Pending Entries") {
                            ForEach(pendingEntries) { entry in
                                Button {
                                    selectedEntryId = entry.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedEntryId == entry.id ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(selectedEntryId == entry.id ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.primaryTransactionDescription ?? entry.counterpartyName)
                                                .font(.headline)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Text("\(entry.linkType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) • \(entry.status.rawValue.capitalized)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text("Total \(Formatters.currency(entry.totalAmount))")
                                                .font(.caption)
                                            Text("Left \(Formatters.currency(entry.pendingAmount))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle(transactions.count > 1 ? "Link Transactions" : "Link to Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task { await submit() }
                    }
                    .disabled(isSaving || isLoading || pendingEntries.isEmpty || selectedEntryId == 0)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            await loadIfNeeded()
        }
    }

    private var totalAmount: Decimal {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private var selectedDirection: TransactionDirection? {
        guard let first = transactions.first else { return nil }
        if transactions.allSatisfy({ $0.direction == first.direction }) {
            return first.direction
        }
        return nil
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true

        guard !transactions.isEmpty else {
            isLoading = false
            errorMessage = "No transactions selected."
            return
        }

        guard let direction = selectedDirection else {
            isLoading = false
            errorMessage = "All selected transactions must have the same direction."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let entries = try await apiClient.pendingEntries()

            switch direction {
            case .inflow:
                pendingEntries = entries.filter { $0.linkType == .splitPayment || $0.linkType == .loan }
            case .outflow:
                pendingEntries = entries.filter { $0.linkType == .debt || $0.linkType == .installment }
            case .reserved:
                pendingEntries = []
            }

            errorMessage = nil
        } catch {
            pendingEntries = []
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard selectedEntryId != 0 else {
            errorMessage = "Select an entry to link."
            return
        }

        let ids = transactions.map(\.id)
        guard !ids.isEmpty else {
            errorMessage = "No transactions selected."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await apiClient.linkToEntry(
                BulkLinkRequest(transactionIds: ids, linkedEntryId: selectedEntryId)
            )
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
