import SwiftUI

struct TransactionAmountPresentation {
    enum TintRole: Equatable {
        case accent
        case normal
        case muted
    }

    let primaryText: String
    let secondaryText: String?

    static func make(for transaction: TransactionWithDetails) -> TransactionAmountPresentation {
        if
            transaction.classification == .splitPayment,
            transaction.linkedEntry?.linkType == .splitPayment,
            let userAmount = transaction.linkedEntry?.userAmount
        {
            return TransactionAmountPresentation(
                primaryText: displayAmount(userAmount, direction: transaction.direction),
                secondaryText: "(over \(Formatters.currency(transaction.amount)))"
            )
        }

        return TransactionAmountPresentation(
            primaryText: displayAmount(transaction.amount, direction: transaction.direction),
            secondaryText: nil
        )
    }

    private static func displayAmount(_ amount: Decimal, direction: TransactionDirection) -> String {
        switch direction {
        case .inflow:
            return "+\(Formatters.currency(amount))"
        case .outflow, .reserved:
            return Formatters.currency(amount)
        }
    }

    static func tintRole(for transaction: TransactionWithDetails) -> TintRole {
        if transaction.isIgnored {
            return .muted
        }

        switch transaction.direction {
        case .inflow:
            return .accent
        case .outflow:
            return .normal
        case .reserved:
            return .muted
        }
    }
}

struct TransactionBadgePresentation {
    struct Badge {
        let title: String
        let tint: Color
    }

    static func titles(for transaction: TransactionWithDetails) -> [String] {
        badges(for: transaction).map(\.title)
    }

    static func badges(for transaction: TransactionWithDetails) -> [Badge] {
        var badges: [Badge] = []

        if let classificationBadge = classificationBadge(for: transaction.classification) {
            badges.append(classificationBadge)
        }

        if transaction.isIgnored {
            badges.append(Badge(title: "Ignored", tint: .gray))
        }

        if let linkedEntryBadge = linkedEntryBadge(for: transaction) {
            badges.append(linkedEntryBadge)
        }

        if let completionBadge = completionBadge(for: transaction) {
            badges.append(completionBadge)
        }

        return badges
    }

    private static func classificationBadge(for classification: TransactionClassification) -> Badge? {
        switch classification {
        case .expense, .income:
            return nil
        case .splitPayment:
            return Badge(title: "Split Payment", tint: .blue)
        case .debtCollection:
            return Badge(title: "Debt Collection", tint: .green)
        case .loanRepayment:
            return Badge(title: "Loan Repayment", tint: .orange)
        case .installmtChrge:
            return Badge(title: "Installment Charge", tint: .orange)
        case .installment:
            return Badge(title: "Installment", tint: .orange)
        case .transfer:
            return Badge(title: "Transfer", tint: .secondary)
        case .lend:
            return Badge(title: "Lend", tint: .blue)
        case .borrow:
            return Badge(title: "Borrow", tint: .purple)
        }
    }

    private static func linkedEntryBadge(for transaction: TransactionWithDetails) -> Badge? {
        guard transaction.hasLinkedEntry else { return nil }
        guard !duplicatesClassificationMeaning(for: transaction) else { return nil }

        return Badge(
            title: LinkedEntryPresentation.ownerBadgeText(for: transaction),
            tint: .blue
        )
    }

    private static func duplicatesClassificationMeaning(for transaction: TransactionWithDetails) -> Bool {
        guard let linkType = transaction.linkedEntry?.linkType else { return false }

        switch (transaction.classification, linkType) {
        case (.splitPayment, .splitPayment), (.installment, .installment):
            return true
        default:
            return false
        }
    }

    private static func completionBadge(for transaction: TransactionWithDetails) -> Badge? {
        guard transaction.linkedEntry?.linkType == .splitPayment else { return nil }
        guard transaction.linkedEntry?.status == .settled else { return nil }

        return Badge(title: "Done", tint: .green)
    }
}

struct TransactionInlineEditState {
    enum Field: Hashable {
        case description, wallet, category, amount
    }

    struct TableSelection: Equatable {
        let rowIds: Set<String>
        let transactionIds: Set<Int>
    }

    var editingTransactionId: Int?
    var editingField: Field?
    var editText: String = ""
    var editWalletId: Int = 0
    var editWalletInitialId: Int?
    var editCategoryId: Int = 0
    var editSubcategoryId: Int = 0
    var selectedRowIds: Set<String> = []

    static func rowId(for transactionId: Int) -> String {
        "t:\(transactionId)"
    }

    mutating func beginTextEdit(transactionId: Int, field: Field, text: String) {
        editText = text
        beginEditing(transactionId: transactionId, field: field)
    }

    mutating func beginWalletEdit(transactionId: Int, walletId: Int) {
        editWalletId = walletId
        editWalletInitialId = walletId
        beginEditing(transactionId: transactionId, field: .wallet)
    }

    mutating func beginCategoryEdit(transactionId: Int, categoryId: Int?, subcategoryId: Int?) {
        editCategoryId = categoryId ?? 0
        editSubcategoryId = subcategoryId ?? 0
        beginEditing(transactionId: transactionId, field: .category)
    }

    mutating func beginEditing(transactionId: Int, field: Field) {
        selectedRowIds = [Self.rowId(for: transactionId)]
        editingTransactionId = transactionId
        editingField = field
    }

    mutating func applyTableSelection(_ rowIds: Set<String>) -> TableSelection {
        let transactionRows = Set(rowIds.filter { $0.hasPrefix("t:") })
        selectedRowIds = transactionRows

        let transactionIds = Set(transactionRows.compactMap { rowId -> Int? in
            guard rowId.hasPrefix("t:") else { return nil }
            return Int(rowId.dropFirst(2))
        })

        if let editingTransactionId, !transactionIds.contains(editingTransactionId) {
            cancelEdit()
        } else if transactionIds.isEmpty {
            cancelEdit()
        }

        return TableSelection(rowIds: transactionRows, transactionIds: transactionIds)
    }

    mutating func syncSelectedTransactions(_ transactionIds: Set<Int>) {
        selectedRowIds = Set(transactionIds.map(Self.rowId(for:)))
    }

    func isEditing(transactionId: Int, field: Field) -> Bool {
        editingTransactionId == transactionId && editingField == field
    }

    mutating func cancelEdit() {
        editingTransactionId = nil
        editingField = nil
        editWalletInitialId = nil
        editText = ""
    }

    mutating func clearSelectionAndEditing() {
        selectedRowIds.removeAll()
        cancelEdit()
    }
}

struct TransactionListView: View {
    private static let rowHorizontalPadding: CGFloat = 0
    private static let transactionRowHeight: CGFloat = 42

    private enum TransactionTableRow: Identifiable {
        case dayHeader(date: String, title: String)
        case transaction(TransactionWithDetails)

        var id: String {
            switch self {
            case .dayHeader(let date, _):
                return "d:\(date)"
            case .transaction(let transaction):
                return "t:\(transaction.id)"
            }
        }
    }

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

    @State private var inlineEdit = TransactionInlineEditState()

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
                let tableRows = buildTableRows(from: viewModel.transactions)

                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clearSelectionAndEditing(bindableViewModel)
                        }

                    Table(tableRows, selection: $inlineEdit.selectedRowIds) {
                        TableColumn("Description") { row in
                            switch row {
                            case .dayHeader(_, let title):
                                Text(title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, Self.rowHorizontalPadding)
                                    .allowsHitTesting(false)
                            case .transaction(let transaction):
                                descriptionCell(
                                    for: transaction,
                                    viewModel: viewModel,
                                    dayHeader: nil
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: Self.transactionRowHeight, alignment: .center)
                                .padding(.horizontal, Self.rowHorizontalPadding)
                                .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                            }
                        }
                        .width(min: 220, ideal: 300, max: 380)

                        TableColumn("Category") { row in
                            switch row {
                            case .dayHeader:
                                Spacer()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                            case .transaction(let transaction):
                                categoryCell(for: transaction, viewModel: viewModel)
                                    .frame(minHeight: Self.transactionRowHeight, alignment: .center)
                                    .padding(.horizontal, Self.rowHorizontalPadding)
                                    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                            }
                        }
                        .width(min: 150, ideal: 190, max: 240)

                        TableColumn("Amount") { row in
                            switch row {
                            case .dayHeader:
                                Spacer()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                            case .transaction(let transaction):
                                amountCell(for: transaction, viewModel: viewModel)
                                    .frame(minHeight: Self.transactionRowHeight, alignment: .center)
                                    .padding(.horizontal, Self.rowHorizontalPadding)
                                    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                            }
                        }
                        .width(min: 110, ideal: 130, max: 170)

                        TableColumn("Wallet") { row in
                            switch row {
                            case .dayHeader:
                                Spacer()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                            case .transaction(let transaction):
                                walletCell(for: transaction, viewModel: viewModel)
                                    .frame(minHeight: Self.transactionRowHeight, alignment: .center)
                                    .padding(.horizontal, Self.rowHorizontalPadding)
                                    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
                            }
                        }
                        .width(min: 120, ideal: 150, max: 190)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    .onChange(of: inlineEdit.selectedRowIds) { _, newValue in
                        let selection = inlineEdit.applyTableSelection(newValue)
                        if selection.transactionIds != bindableViewModel.selectedIds {
                            bindableViewModel.selectedIds = selection.transactionIds
                        }
                    }
                    .onChange(of: bindableViewModel.selectedIds) { _, newValue in
                        let mapped = Set(newValue.map { "t:\($0)" })
                        if mapped != inlineEdit.selectedRowIds {
                            inlineEdit.syncSelectedTransactions(newValue)
                        }
                    }
                    .onExitCommand {
                        clearSelectionAndEditing(bindableViewModel)
                    }
                }
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

    private func buildTableRows(from transactions: [TransactionWithDetails]) -> [TransactionTableRow] {
        var rows: [TransactionTableRow] = []
        var lastDate: String?
        for transaction in transactions {
            if transaction.date != lastDate {
                rows.append(.dayHeader(date: transaction.date, title: daySectionTitle(for: transaction.date)))
                lastDate = transaction.date
            }
            rows.append(.transaction(transaction))
        }
        return rows
    }

    private func descriptionCell(for transaction: TransactionWithDetails, viewModel: TransactionViewModel, dayHeader: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dayHeader {
                Text(dayHeader)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }

            EditableTextCell(
                value: transaction.description?.isEmpty == false ? transaction.description! : "Untitled Transaction",
                isEditing: isEditing(transaction, field: .description),
                editText: $inlineEdit.editText,
                onBeginEdit: { beginTextEdit(transaction, field: .description, text: transaction.description ?? "", viewModel: viewModel) },
                onCommit: { newValue in commitDescriptionEdit(transaction, newValue: newValue, viewModel: viewModel) },
                onCancel: { cancelEdit() }
            )

            if !isEditing(transaction, field: .description) {
                HStack(spacing: 6) {
                    if let time = transaction.time {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(TransactionBadgePresentation.badges(for: transaction).enumerated()), id: \.offset) { _, badge in
                        self.badge(badge.title, tint: badge.tint)
                    }
                }
            }
        }
    }

    private func walletCell(for transaction: TransactionWithDetails, viewModel: TransactionViewModel) -> some View {
        Group {
            if isEditing(transaction, field: .wallet) {
                HStack(spacing: 4) {
                    Picker("Wallet", selection: $inlineEdit.editWalletId) {
                        ForEach(walletStore.wallets) { wallet in
                            Text(walletTitle(for: wallet)).tag(wallet.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: inlineEdit.editWalletId) { _, newWalletId in
                        guard let initial = inlineEdit.editWalletInitialId else { return }
                        guard newWalletId != initial else { return }
                        commitWalletEdit(transaction, newWalletId: newWalletId, viewModel: viewModel)
                    }

                    Button {
                        cancelEdit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .onExitCommand { cancelEdit() }
            } else {
                Text(walletTitle(for: transaction))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        beginWalletEdit(transaction, viewModel: viewModel)
                    })
            }
        }
    }

    private func categoryCell(for transaction: TransactionWithDetails, viewModel: TransactionViewModel) -> some View {
        EditableCategoryPicker(
            displayText: categoryTitle(for: transaction),
            isEditing: isEditing(transaction, field: .category),
            isUncategorized: transaction.categoryId == nil && transaction.subcategoryId == nil,
            categories: categoryStore.categories,
            selectedCategoryId: $inlineEdit.editCategoryId,
            selectedSubcategoryId: $inlineEdit.editSubcategoryId,
            onBeginEdit: {
                beginCategoryEdit(transaction, viewModel: viewModel)
            },
            onCommit: { catId, subId in commitCategoryEdit(transaction, categoryId: catId, subcategoryId: subId, viewModel: viewModel) },
            onCancel: { cancelEdit() }
        )
    }

    private func amountCell(for transaction: TransactionWithDetails, viewModel: TransactionViewModel) -> some View {
        Group {
            if isEditing(transaction, field: .amount) {
                EditableTextCell(
                    value: amountTitle(for: transaction),
                    isEditing: true,
                    editText: $inlineEdit.editText,
                    alignment: .leading,
                    onBeginEdit: { beginTextEdit(transaction, field: .amount, text: transaction.amount.description, viewModel: viewModel) },
                    onCommit: { newValue in commitAmountEdit(transaction, newValue: newValue, viewModel: viewModel) },
                    onCancel: { cancelEdit() }
                )
            } else {
                let presentation = amountPresentation(for: transaction)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.primaryText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(amountColor(for: transaction))
                        .lineLimit(1)

                    if let secondaryText = presentation.secondaryText {
                        Text(secondaryText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(amountColor(for: transaction).opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    beginTextEdit(transaction, field: .amount, text: transaction.amount.description, viewModel: viewModel)
                })
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for transaction: TransactionWithDetails, viewModel: TransactionViewModel) -> some View {
        Button("Details") {
            selectedTransaction = transaction
        }
        
        Menu("Mark as") {
            if canMarkAsSplit(transaction) {
                Button("Split payment") {
                    activeActionSheet = .markSplit(transaction)
                }
            }

            if canMarkAsLoan(transaction) {
                Button("Loan") {
                    activeActionSheet = .markLoan(transaction)
                }
            }

            if canMarkAsDebt(transaction) {
                Button("Debt") {
                    activeActionSheet = .markDebt(transaction)
                }
            }

            if canMarkAsInstallment(transaction) {
                Button("Installment plan") {
                    activeActionSheet = .markInstallment(transaction)
                }
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
            Button("See reimbursements") {
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
            Button("Resolve calibration") {
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

            if selectedTransactions.contains(where: { !$0.isIgnored }) {
                Button("Ignore") {
                    Task {
                        await viewModel.ignoreSelected()
                        await walletStore.refresh()
                    }
                }
                .disabled(viewModel.isLoading)
            }

            if selectedTransactions.contains(where: { $0.isIgnored }) {
                Button("Unignore") {
                    Task {
                        await viewModel.unignoreSelected()
                        await walletStore.refresh()
                    }
                }
                .disabled(viewModel.isLoading)
            }

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

            Button("Unselect") {
                clearSelectionAndEditing(viewModel)
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
        amountPresentation(for: transaction).primaryText
    }

    private func amountPresentation(for transaction: TransactionWithDetails) -> TransactionAmountPresentation {
        TransactionAmountPresentation.make(for: transaction)
    }

    private func amountColor(for transaction: TransactionWithDetails) -> Color {
        switch TransactionAmountPresentation.tintRole(for: transaction) {
        case .accent:
            return .green
        case .normal:
            return .primary
        case .muted:
            return .secondary
        }
    }

    private func walletTitle(for wallet: WalletWithBalance) -> String {
        if let emoji = wallet.emoji, !emoji.isEmpty {
            return "\(emoji) \(wallet.name)"
        }
        return wallet.name
    }

    private func walletTitle(for transaction: TransactionWithDetails) -> String {
        let resolved = walletStore.wallet(for: transaction.walletId)
        if let resolved {
            return walletTitle(for: resolved)
        }

        let name = transaction.walletName ?? "Unknown"
        return name
    }

    private func categoryTitle(for transaction: TransactionWithDetails) -> String {
        guard let categoryId = transaction.categoryId else {
            return "Uncategorized"
        }

        let category = categoryStore.categories.first(where: { $0.id == categoryId })
        let emojiPrefix: String = {
            if let emoji = category?.emoji, !emoji.isEmpty {
                return "\(emoji) "
            }
            return ""
        }()

        if let subcategoryName = transaction.subcategoryName, !subcategoryName.isEmpty {
            return emojiPrefix + subcategoryName
        }

        if let categoryName = category?.name {
            return emojiPrefix + categoryName
        }

        if let categoryName = transaction.categoryName, !categoryName.isEmpty {
            return emojiPrefix + categoryName
        }

        return "Uncategorized"
    }

    private func isEditing(_ transaction: TransactionWithDetails, field: TransactionInlineEditState.Field) -> Bool {
        inlineEdit.isEditing(transactionId: transaction.id, field: field)
    }

    private func beginTextEdit(
        _ transaction: TransactionWithDetails,
        field: TransactionInlineEditState.Field,
        text: String,
        viewModel: TransactionViewModel
    ) {
        inlineEdit.beginTextEdit(transactionId: transaction.id, field: field, text: text)
        viewModel.selectedIds = [transaction.id]
    }

    private func beginWalletEdit(_ transaction: TransactionWithDetails, viewModel: TransactionViewModel) {
        inlineEdit.beginWalletEdit(transactionId: transaction.id, walletId: transaction.walletId)
        viewModel.selectedIds = [transaction.id]
    }

    private func beginCategoryEdit(_ transaction: TransactionWithDetails, viewModel: TransactionViewModel) {
        inlineEdit.beginCategoryEdit(
            transactionId: transaction.id,
            categoryId: transaction.categoryId,
            subcategoryId: transaction.subcategoryId
        )
        viewModel.selectedIds = [transaction.id]
    }

    private func cancelEdit() {
        inlineEdit.cancelEdit()
    }

    private func clearSelectionAndEditing(_ viewModel: TransactionViewModel) {
        inlineEdit.clearSelectionAndEditing()
        viewModel.selectedIds.removeAll()
    }

    private static let groupedDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let groupedDateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func daySectionTitle(for date: String) -> String {
        guard let parsedDate = Self.groupedDateParser.date(from: date) else {
            return date
        }
        return Self.groupedDateTitleFormatter.string(from: parsedDate)
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
