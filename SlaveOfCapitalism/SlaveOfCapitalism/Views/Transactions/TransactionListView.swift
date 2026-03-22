import SwiftUI

struct TransactionListView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(WalletStore.self) private var walletStore

    @State private var viewModel: TransactionViewModel?
    @State private var isShowingAddSheet = false
    @State private var selectedTransaction: TransactionWithDetails?
    @State private var didRefreshReferenceData = false
    @State private var pendingDeleteIds: Set<Int> = []
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading transactions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        initializeViewModelIfNeeded()
                    }
            }
        }
        .navigationTitle("Transactions")
    }

    @ViewBuilder
    private func content(for viewModel: TransactionViewModel) -> some View {
        @Bindable var bindableViewModel = viewModel

        VStack(spacing: 0) {
            if let error = viewModel.error {
                errorBanner(message: error.localizedDescription) {
                    Task {
                        await refreshLedger(viewModel)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ProgressView("Loading transactions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.transactions.isEmpty {
                ContentUnavailableView {
                    Label("No Transactions", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("No transactions in \(Formatters.monthYear(year: viewModel.selectedYear, month: viewModel.selectedMonth)).")
                } actions: {
                    Button("Add Transaction") {
                        isShowingAddSheet = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.transactions, selection: $bindableViewModel.selectedIds) {
                    TableColumn("Date") { transaction in
                        interactiveCell(for: transaction) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transaction.date)
                                if let time = transaction.time {
                                    Text(time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .width(min: 110, max: 130)

                    TableColumn("Description") { transaction in
                        interactiveCell(for: transaction) {
                            TransactionRow(transaction: transaction)
                        }
                    }

                    TableColumn("Wallet") { transaction in
                        interactiveCell(for: transaction) {
                            Text(transaction.walletName ?? walletStore.wallet(for: transaction.walletId)?.name ?? "Unknown")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .width(min: 120, ideal: 140)

                    TableColumn("Category") { transaction in
                        interactiveCell(for: transaction) {
                            Text(categoryTitle(for: transaction))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(transaction.categoryId == nil && transaction.subcategoryId == nil ? .secondary : .primary)
                        }
                    }
                    .width(min: 140, ideal: 160)

                    TableColumn("Amount") { transaction in
                        interactiveCell(for: transaction) {
                            Text(amountTitle(for: transaction))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(amountColor(for: transaction))
                        }
                    }
                    .width(min: 100, ideal: 120)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .padding(24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                MonthYearPicker(year: $bindableViewModel.selectedYear, month: $bindableViewModel.selectedMonth)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.selectedIds.isEmpty {
                bulkActionBar(for: viewModel)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddTransactionSheet(wallets: walletStore.wallets, categories: categoryStore.categories) {
                await refreshAfterMutation(viewModel)
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailSheet(transaction: transaction, wallets: walletStore.wallets, categories: categoryStore.categories) {
                await refreshAfterMutation(viewModel)
            }
        }
        .task(id: viewModel.monthKey) {
            await refreshLedger(viewModel)
        }
        .task {
            guard !didRefreshReferenceData else { return }
            didRefreshReferenceData = true
            await refreshReferenceDataIfNeeded()
        }
        .confirmationDialog(
            pendingDeleteIds.count > 1 ? "Delete \(pendingDeleteIds.count) transactions?" : "Delete transaction?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await performConfirmedDelete(viewModel)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func interactiveCell<Content: View>(
        for transaction: TransactionWithDetails,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .contentShape(Rectangle())
            .contextMenu {
                rowContextMenu(for: transaction)
            }
            .onTapGesture {
                selectedTransaction = transaction
            }
    }

    @ViewBuilder
    private func rowContextMenu(for transaction: TransactionWithDetails) -> some View {
        Button("Open Details") {
            selectedTransaction = transaction
        }

        Button(transaction.isIgnored ? "Unignore" : "Ignore") {
            Task {
                viewModel?.selectedIds = [transaction.id]
                if transaction.isIgnored {
                    await viewModel?.unignoreSelected()
                } else {
                    await viewModel?.ignoreSelected()
                }
                await walletStore.refresh()
            }
        }

        Button("Delete", role: .destructive) {
            requestDelete(ids: [transaction.id])
        }

        Divider()

        Button("Mark as Split (Task 12)") {}
            .disabled(true)
        Button("Mark as Loan (Task 12)") {}
            .disabled(true)
        Button("Mark as Debt (Task 12)") {}
            .disabled(true)
        Button("Link to Entry (Task 12)") {}
            .disabled(true)
    }

    private func bulkActionBar(for viewModel: TransactionViewModel) -> some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedIds.count) selected")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button("Ignore") {
                Task {
                    await viewModel.ignoreSelected()
                    await walletStore.refresh()
                }
            }
            .disabled(viewModel.isLoading)

            Button("Unignore") {
                Task {
                    await viewModel.unignoreSelected()
                    await walletStore.refresh()
                }
            }
            .disabled(viewModel.isLoading)

            Button("Delete", role: .destructive) {
                requestDelete(ids: viewModel.selectedIds)
            }
            .disabled(viewModel.isLoading)

            Button("Clear") {
                viewModel.selectedIds.removeAll()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        viewModel = TransactionViewModel(apiClient: apiClient)
    }

    private func refreshLedger(_ viewModel: TransactionViewModel) async {
        await viewModel.load()
    }

    private func refreshAfterMutation(_ viewModel: TransactionViewModel) async {
        await refreshLedger(viewModel)
        await walletStore.refresh()
    }

    private func refreshReferenceDataIfNeeded() async {
        if walletStore.wallets.isEmpty {
            await walletStore.refresh()
        }

        if categoryStore.categories.isEmpty {
            await categoryStore.refresh()
        }
    }

    private func amountTitle(for transaction: TransactionWithDetails) -> String {
        let prefix: String
        switch transaction.direction {
        case .inflow:
            prefix = "+"
        case .outflow:
            prefix = "-"
        case .reserved:
            prefix = ""
        }
        return prefix + Formatters.currency(transaction.amount)
    }

    private func amountColor(for transaction: TransactionWithDetails) -> Color {
        switch transaction.direction {
        case .inflow:
            return .green
        case .outflow:
            return .red
        case .reserved:
            return .orange
        }
    }

    private func categoryTitle(for transaction: TransactionWithDetails) -> String {
        transaction.subcategoryName ?? transaction.categoryName ?? "Uncategorized"
    }

    private func requestDelete(ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIds = ids
        isShowingDeleteConfirmation = true
    }

    private func performConfirmedDelete(_ viewModel: TransactionViewModel) async {
        let ids = pendingDeleteIds
        pendingDeleteIds = []
        guard !ids.isEmpty else { return }

        viewModel.selectedIds = ids
        await viewModel.deleteSelected()
        await walletStore.refresh()
    }
}
