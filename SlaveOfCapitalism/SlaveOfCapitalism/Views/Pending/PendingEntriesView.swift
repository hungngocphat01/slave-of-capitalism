import SwiftUI

struct PendingEntriesView: View {
    @Environment(APIClient.self) private var apiClient

    @State private var viewModel: PendingViewModel?
    @State private var isOwedExpanded = true
    @State private var isDebtExpanded = true
    @State private var isInstallmentExpanded = true
    @State private var linkingEntry: LinkedEntryWithDetails?
    @State private var selectedTransactionId = 0
    @State private var isLoadingCandidates = false

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading pending entries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        initializeViewModelIfNeeded()
                    }
            }
        }
        .navigationTitle("Pending")
    }

    @ViewBuilder
    private func content(for viewModel: PendingViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error {
                    errorBanner(message: error.localizedDescription) {
                        Task { await viewModel.load() }
                    }
                }

                section(
                    title: "People Owe Me",
                    total: viewModel.totalOwed,
                    tint: .green,
                    isExpanded: $isOwedExpanded,
                    entries: viewModel.owedEntries,
                    emptyMessage: "No pending reimbursements."
                )

                section(
                    title: "I Owe",
                    total: viewModel.totalDebt,
                    tint: .red,
                    isExpanded: $isDebtExpanded,
                    entries: viewModel.debtEntries,
                    emptyMessage: "No pending debts."
                )

                section(
                    title: "Installments",
                    total: viewModel.totalInstallments,
                    tint: .orange,
                    isExpanded: $isInstallmentExpanded,
                    entries: viewModel.installmentEntries,
                    emptyMessage: "No active installments."
                )
            }
            .padding(24)
        }
        .overlay {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView("Loading pending entries...")
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading || viewModel.isLinking)
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(item: $linkingEntry) { entry in
            linkTransactionSheet(for: entry, viewModel: viewModel)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        total: Decimal,
        tint: Color,
        isExpanded: Binding<Bool>,
        entries: [LinkedEntryWithDetails],
        emptyMessage: String
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if entries.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        entryCard(entry: entry, tint: tint)
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(Formatters.currency(total))
                    .font(.headline)
                    .foregroundStyle(tint)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func entryCard(entry: LinkedEntryWithDetails, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.counterpartyName)
                        .font(.headline)

                    if let description = entry.primaryTransactionDescription, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                Spacer()

                Text(Formatters.currency(entry.pendingAmount))
                    .font(.headline)
                    .foregroundStyle(tint)
            }

            HStack(spacing: 8) {
                badge(text: linkTypeLabel(for: entry.linkType), tint: .secondary)
                badge(text: statusLabel(for: entry.status), tint: statusColor(for: entry.status))
                Text(String(entry.createdAt.prefix(10)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if !entry.linkedTransactions.isEmpty {
                DisclosureGroup("\(paymentsLabel(for: entry.linkType)) (\(entry.linkedTransactions.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entry.linkedTransactions) { linkedTransaction in
                            HStack {
                                Text("• \(linkedTransaction.date ?? "N/A")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(Formatters.currency(linkedTransaction.amount))
                                    .font(.caption)
                                if let description = linkedTransaction.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }

            if entry.status != .settled {
                HStack {
                    Spacer()
                    Button("Link Transaction") {
                        linkingEntry = entry
                    }
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func linkTransactionSheet(for entry: LinkedEntryWithDetails, viewModel: PendingViewModel) -> some View {
        NavigationStack {
            Group {
                if isLoadingCandidates {
                    ProgressView("Loading candidate transactions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let candidates = viewModel.linkableTransactions(for: entry.id)
                    if candidates.isEmpty {
                        ContentUnavailableView {
                            Label("No Candidate Transactions", systemImage: "tray")
                        } description: {
                            Text("Create a matching transaction first, then link it here.")
                        }
                    } else {
                        List(candidates) { transaction in
                            Button {
                                selectedTransactionId = transaction.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedTransactionId == transaction.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedTransactionId == transaction.id ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transaction.description ?? "Transaction #\(transaction.id)")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(transaction.date) • \(transaction.classification.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Text(Formatters.currency(transaction.amount))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .navigationTitle("Link Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        linkingEntry = nil
                        viewModel.clearLinkableTransactions(for: entry.id)
                    }
                    .disabled(viewModel.isLinking)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task {
                            let didLink = await viewModel.linkTransaction(entryId: entry.id, transactionId: selectedTransactionId)
                            if didLink {
                                linkingEntry = nil
                            }
                        }
                    }
                    .disabled(viewModel.isLinking || isLoadingCandidates || selectedTransactionId == 0)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            await loadCandidates(for: entry, viewModel: viewModel)
        }
    }

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        viewModel = PendingViewModel(apiClient: apiClient)
    }

    private func loadCandidates(for entry: LinkedEntryWithDetails, viewModel: PendingViewModel) async {
        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        await viewModel.loadLinkableTransactions(for: entry)
        let candidates = viewModel.linkableTransactions(for: entry.id)
        selectedTransactionId = candidates.first?.id ?? 0
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func linkTypeLabel(for linkType: LinkType) -> String {
        switch linkType {
        case .splitPayment:
            return "💰 Split Payment"
        case .loan:
            return "💸 Loan"
        case .debt:
            return "🏦 Debt"
        case .installment:
            return "💳 Installment"
        }
    }

    private func statusLabel(for status: LinkStatus) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .partial:
            return "Partial"
        case .settled:
            return "Settled"
        }
    }

    private func statusColor(for status: LinkStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .partial:
            return .blue
        case .settled:
            return .green
        }
    }

    private func paymentsLabel(for linkType: LinkType) -> String {
        switch linkType {
        case .splitPayment, .loan:
            return "Payments Received"
        case .debt:
            return "Repayments Made"
        case .installment:
            return "Charges Recorded"
        }
    }
}

#Preview {
    PendingEntriesView()
        .environment(APIClient())
}
