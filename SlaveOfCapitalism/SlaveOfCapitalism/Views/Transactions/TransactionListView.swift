import SwiftUI

struct TransactionListView: View {
    private enum TransactionActionSheet: Identifiable {
        case markSplit(TransactionWithDetails)
        case markLoan(TransactionWithDetails)
        case markDebt(TransactionWithDetails)
        case markInstallment(TransactionWithDetails)
        case reclassify(TransactionWithDetails)
        case link([TransactionWithDetails])
        case resolveCalibration(TransactionWithDetails)
        case merge([TransactionWithDetails])
        case reimbursements(TransactionWithDetails)

        var id: String {
            switch self {
            case .markSplit(let transaction):
                return "markSplit-\(transaction.id)"
            case .markLoan(let transaction):
                return "markLoan-\(transaction.id)"
            case .markDebt(let transaction):
                return "markDebt-\(transaction.id)"
            case .markInstallment(let transaction):
                return "markInstallment-\(transaction.id)"
            case .reclassify(let transaction):
                return "reclassify-\(transaction.id)"
            case .link(let transactions):
                return "link-\(transactions.map(\.id).sorted().map(String.init).joined(separator: "-"))"
            case .resolveCalibration(let transaction):
                return "resolve-\(transaction.id)"
            case .merge(let transactions):
                return "merge-\(transactions.map(\.id).sorted().map(String.init).joined(separator: "-"))"
            case .reimbursements(let transaction):
                return "reimbursements-\(transaction.id)"
            }
        }
    }

    @Environment(APIClient.self) private var apiClient
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(WalletStore.self) private var walletStore

    @State private var viewModel: TransactionViewModel?
    @State private var isShowingAddSheet = false
    @State private var selectedTransaction: TransactionWithDetails?
    @State private var activeActionSheet: TransactionActionSheet?
    @State private var didRefreshReferenceData = false
    @State private var pendingDeleteIds: Set<Int> = []
    @State private var isShowingDeleteConfirmation = false

    @State private var editingTransactionId: Int?
    @State private var editingField: EditableField?
    @State private var editText: String = ""
    @State private var editWalletId: Int = 0
    @State private var editCategoryId: Int = 0
    @State private var editSubcategoryId: Int = 0

    private enum EditableField: Hashable {
        case date, description, wallet, category, amount
    }

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
            MonthYearPicker(year: $bindableViewModel.selectedYear, month: $bindableViewModel.selectedMonth)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

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
                        VStack(alignment: .leading, spacing: 2) {
                            EditableTextCell(
                                value: transaction.date,
                                isEditing: isEditing(transaction, field: .date),
                                editText: $editText,
                                font: .body,
                                onBeginEdit: { beginEdit(transaction, field: .date, text: transaction.date) },
                                onCommit: { newValue in commitDateEdit(transaction, newValue: newValue, viewModel: viewModel) },
                                onCancel: { cancelEdit() }
                            )
                            if let time = transaction.time, !isEditing(transaction, field: .date) {
                                Text(time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                    }
                    .width(min: 110, max: 130)

                    TableColumn("Description") { transaction in
                        VStack(alignment: .leading, spacing: 4) {
                            EditableTextCell(
                                value: transaction.description?.isEmpty == false ? transaction.description! : "Untitled Transaction",
                                isEditing: isEditing(transaction, field: .description),
                                editText: $editText,
                                onBeginEdit: { beginEdit(transaction, field: .description, text: transaction.description ?? "") },
                                onCommit: { newValue in commitDescriptionEdit(transaction, newValue: newValue, viewModel: viewModel) },
                                onCancel: { cancelEdit() }
                            )

                            if !isEditing(transaction, field: .description) {
                                HStack(spacing: 6) {
                                    Text(transaction.classification.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if transaction.isIgnored {
                                        badge("Ignored", tint: .orange)
                                    }
                                    if transaction.hasLinkedEntry {
                                        badge("Linked", tint: .blue)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                    }

                    TableColumn("Wallet") { transaction in
                        Group {
                            if isEditing(transaction, field: .wallet) {
                                HStack(spacing: 4) {
                                    Picker("Wallet", selection: $editWalletId) {
                                        ForEach(walletStore.wallets) { wallet in
                                            Text(wallet.name).tag(wallet.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()

                                    Button("OK") {
                                        commitWalletEdit(transaction, newWalletId: editWalletId, viewModel: viewModel)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button {
                                        cancelEdit()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                                .onExitCommand { cancelEdit() }
                            } else {
                                Text(transaction.walletName ?? walletStore.wallet(for: transaction.walletId)?.name ?? "Unknown")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editWalletId = transaction.walletId
                                        editingTransactionId = transaction.id
                                        editingField = .wallet
                                    }
                            }
                        }
                        .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                    }
                    .width(min: 120, ideal: 140)

                    TableColumn("Category") { transaction in
                        EditableCategoryPicker(
                            displayText: categoryTitle(for: transaction),
                            isEditing: isEditing(transaction, field: .category),
                            isUncategorized: transaction.categoryId == nil && transaction.subcategoryId == nil,
                            categories: categoryStore.categories,
                            selectedCategoryId: $editCategoryId,
                            selectedSubcategoryId: $editSubcategoryId,
                            onBeginEdit: {
                                editCategoryId = transaction.categoryId ?? 0
                                editSubcategoryId = transaction.subcategoryId ?? 0
                                editingTransactionId = transaction.id
                                editingField = .category
                            },
                            onCommit: { catId, subId in commitCategoryEdit(transaction, categoryId: catId, subcategoryId: subId, viewModel: viewModel) },
                            onCancel: { cancelEdit() }
                        )
                        .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                    }
                    .width(min: 140, ideal: 160)

                    TableColumn("Amount") { transaction in
                        EditableTextCell(
                            value: amountTitle(for: transaction),
                            isEditing: isEditing(transaction, field: .amount),
                            editText: $editText,
                            alignment: .trailing,
                            foregroundStyle: AnyShapeStyle(amountColor(for: transaction)),
                            onBeginEdit: { beginEdit(transaction, field: .amount, text: transaction.amount.description) },
                            onCommit: { newValue in commitAmountEdit(transaction, newValue: newValue, viewModel: viewModel) },
                            onCancel: { cancelEdit() }
                        )
                        .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                    }
                    .width(min: 100, ideal: 120)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .padding(24)
            }
        }
        .toolbar {
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
        .sheet(item: $activeActionSheet) { action in
            actionSheetView(action, viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingDeleteConfirmation) {
            ConfirmationDialog(
                title: pendingDeleteIds.count > 1 ? "Delete \(pendingDeleteIds.count) transactions?" : "Delete transaction?",
                message: "This action cannot be undone.",
                confirmButtonTitle: "Delete",
                isDestructive: true,
                onCancel: {
                    isShowingDeleteConfirmation = false
                },
                onConfirm: {
                    isShowingDeleteConfirmation = false
                    Task {
                        await performConfirmedDelete(viewModel)
                    }
                }
            )
        }
        .task(id: viewModel.monthKey) {
            await refreshLedger(viewModel)
        }
        .task {
            guard !didRefreshReferenceData else { return }
            didRefreshReferenceData = true
            await refreshReferenceDataIfNeeded()
        }
    }

    @ViewBuilder
    private func actionSheetView(_ action: TransactionActionSheet, viewModel: TransactionViewModel) -> some View {
        switch action {
        case .markSplit(let transaction):
            MarkAsSplitSheet(apiClient: apiClient, transaction: transaction) {
                await refreshAfterMutation(viewModel)
            }
        case .markLoan(let transaction):
            MarkAsLoanSheet(apiClient: apiClient, transaction: transaction) {
                await refreshAfterMutation(viewModel)
            }
        case .markDebt(let transaction):
            MarkAsDebtSheet(apiClient: apiClient, transaction: transaction) {
                await refreshAfterMutation(viewModel)
            }
        case .markInstallment(let transaction):
            MarkAsInstallmentSheet(apiClient: apiClient, transaction: transaction) {
                await refreshAfterMutation(viewModel)
            }
        case .reclassify(let transaction):
            ReclassifySheet(apiClient: apiClient, transaction: transaction) {
                await refreshAfterMutation(viewModel)
            }
        case .link(let transactions):
            LinkToEntrySheet(apiClient: apiClient, transactions: transactions) {
                await refreshAfterMutation(viewModel)
            }
        case .resolveCalibration(let transaction):
            ResolveCalibrationSheet(
                apiClient: apiClient,
                calibration: transaction,
                categories: categoryStore.categories,
                wallets: walletStore.wallets
            ) {
                await refreshAfterMutation(viewModel)
            }
        case .merge(let transactions):
            MergeTransactionsSheet(
                apiClient: apiClient,
                transactions: transactions,
                categories: categoryStore.categories
            ) {
                await refreshAfterMutation(viewModel)
            }
        case .reimbursements(let transaction):
            ReimbursementsSheet(apiClient: apiClient, transaction: transaction)
        }
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func rowContextMenu(for transaction: TransactionWithDetails, viewModel: TransactionViewModel) -> some View {
        Button("Open Details") {
            selectedTransaction = transaction
        }

        if canMarkAsSplit(transaction) {
            Button("Mark as Split") {
                activeActionSheet = .markSplit(transaction)
            }
        }

        if canMarkAsLoan(transaction) {
            Button("Mark as Loan") {
                activeActionSheet = .markLoan(transaction)
            }
        }

        if canMarkAsDebt(transaction) {
            Button("Mark as Debt") {
                activeActionSheet = .markDebt(transaction)
            }
        }

        if canMarkAsInstallment(transaction) {
            Button("Mark as Installment") {
                activeActionSheet = .markInstallment(transaction)
            }
        }

        if canLinkToEntry(transaction) {
            Button("Link to Entry") {
                activeActionSheet = .link([transaction])
            }
        }

        if transaction.isLinkedToEntry {
            Button("Unlink") {
                Task {
                    await unlink(transaction, viewModel: viewModel)
                }
            }
        }

        if transaction.hasLinkedEntry {
            Button("See Reimbursements") {
                activeActionSheet = .reimbursements(transaction)
            }

            Button("Unclassify") {
                Task {
                    await unclassify(transaction, viewModel: viewModel)
                }
            }
        } else {
            Button("Reclassify") {
                activeActionSheet = .reclassify(transaction)
            }
        }

        if transaction.isCalibration {
            Button("Resolve Calibration") {
                activeActionSheet = .resolveCalibration(transaction)
            }
        }

        Divider()

        Button(transaction.isIgnored ? "Unignore" : "Ignore") {
            Task {
                viewModel.selectedIds = [transaction.id]
                if transaction.isIgnored {
                    await viewModel.unignoreSelected()
                } else {
                    await viewModel.ignoreSelected()
                }
                await walletStore.refresh()
            }
        }

        Button("Delete", role: .destructive) {
            requestDelete(ids: [transaction.id])
        }
    }

    private func bulkActionBar(for viewModel: TransactionViewModel) -> some View {
        let selectedTransactions = selectedTransactions(for: viewModel)

        return HStack(spacing: 12) {
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

            Button("Link to Entry") {
                activeActionSheet = .link(selectedTransactions)
            }
            .disabled(viewModel.isLoading || !canBulkLink(selectedTransactions))

            Button("Merge") {
                activeActionSheet = .merge(selectedTransactions)
            }
            .disabled(viewModel.isLoading || !canMerge(selectedTransactions))

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

    private func isEditing(_ transaction: TransactionWithDetails, field: EditableField) -> Bool {
        editingTransactionId == transaction.id && editingField == field
    }

    private func beginEdit(_ transaction: TransactionWithDetails, field: EditableField, text: String) {
        editText = text
        editingTransactionId = transaction.id
        editingField = field
    }

    private func cancelEdit() {
        editingTransactionId = nil
        editingField = nil
        editText = ""
    }

    private static let dateValidator: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func commitDateEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != transaction.date, Self.dateValidator.date(from: trimmed) != nil else {
            cancelEdit()
            return
        }
        cancelEdit()
        Task {
            await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(date: trimmed))
            await walletStore.refresh()
        }
    }

    private func commitDescriptionEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (transaction.description ?? "") else {
            cancelEdit()
            return
        }
        cancelEdit()
        Task {
            await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(description: trimmed))
        }
    }

    private func commitWalletEdit(_ transaction: TransactionWithDetails, newWalletId: Int, viewModel: TransactionViewModel) {
        guard newWalletId != transaction.walletId else {
            cancelEdit()
            return
        }
        cancelEdit()
        Task {
            await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(walletId: newWalletId))
            await walletStore.refresh()
        }
    }

    private func commitCategoryEdit(_ transaction: TransactionWithDetails, categoryId: Int?, subcategoryId: Int?, viewModel: TransactionViewModel) {
        guard categoryId != transaction.categoryId || subcategoryId != transaction.subcategoryId else {
            cancelEdit()
            return
        }
        cancelEdit()
        Task {
            await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(categoryId: categoryId, subcategoryId: subcategoryId))
        }
    }

    private func commitAmountEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
        guard let amount = Decimal(string: newValue), amount > 0, amount != transaction.amount else {
            cancelEdit()
            return
        }
        cancelEdit()
        Task {
            await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(amount: amount))
            await walletStore.refresh()
        }
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

    private func canMarkAsSplit(_ transaction: TransactionWithDetails) -> Bool {
        transaction.direction == .outflow && transaction.classification == .expense
    }

    private func canMarkAsLoan(_ transaction: TransactionWithDetails) -> Bool {
        transaction.direction == .outflow && (transaction.classification == .lend || transaction.classification == .expense)
    }

    private func canMarkAsDebt(_ transaction: TransactionWithDetails) -> Bool {
        transaction.direction == .inflow && (transaction.classification == .borrow || transaction.classification == .income)
    }

    private func canMarkAsInstallment(_ transaction: TransactionWithDetails) -> Bool {
        transaction.direction == .outflow
            && transaction.classification == .expense
            && walletType(for: transaction) == .credit
    }

    private func walletType(for transaction: TransactionWithDetails) -> WalletType? {
        if let walletType = transaction.walletType, let parsed = WalletType(rawValue: walletType) {
            return parsed
        }
        return walletStore.wallet(for: transaction.walletId)?.walletType
    }

    private func canLinkToEntry(_ transaction: TransactionWithDetails) -> Bool {
        switch transaction.classification {
        case .debtCollection, .loanRepayment, .installmtChrge, .income:
            return true
        default:
            return false
        }
    }

    private func selectedTransactions(for viewModel: TransactionViewModel) -> [TransactionWithDetails] {
        viewModel.transactions
            .filter { viewModel.selectedIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func canBulkLink(_ transactions: [TransactionWithDetails]) -> Bool {
        guard let first = transactions.first else { return false }
        guard first.direction != .reserved else { return false }
        return transactions.allSatisfy { $0.direction == first.direction && canLinkToEntry($0) }
    }

    private func canMerge(_ transactions: [TransactionWithDetails]) -> Bool {
        guard transactions.count >= 2, let first = transactions.first else { return false }

        let sameWallet = transactions.allSatisfy { $0.walletId == first.walletId }
        let sameDirection = transactions.allSatisfy { $0.direction == first.direction }
        let allowedClassifications = transactions.allSatisfy { $0.classification == .expense || $0.classification == .income }
        let noCalibration = transactions.allSatisfy { !$0.isCalibration }

        return sameWallet && sameDirection && allowedClassifications && noCalibration
    }

    private func unlink(_ transaction: TransactionWithDetails, viewModel: TransactionViewModel) async {
        do {
            try await apiClient.unlinkTransaction(id: transaction.id)
            await refreshAfterMutation(viewModel)
        } catch {
            assign(error: error, to: viewModel)
        }
    }

    private func unclassify(_ transaction: TransactionWithDetails, viewModel: TransactionViewModel) async {
        do {
            try await apiClient.unclassifyTransaction(id: transaction.id)
            await refreshAfterMutation(viewModel)
        } catch {
            assign(error: error, to: viewModel)
        }
    }

    private func assign(error: Error, to viewModel: TransactionViewModel) {
        if error is CancellationError {
            return
        }

        if let apiError = error as? APIError {
            viewModel.error = apiError
        } else {
            viewModel.error = .networkError(error)
        }
    }
}
