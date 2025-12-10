<script lang="ts">
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import { settings } from "$lib/stores/settings";
    import type {
        PopulatedTransaction,
        Wallet,
        CategoryWithSubcategories,
        Subcategory,
        Direction,
        Classification,
    } from "$lib/api/types";
    import TransactionContextMenu from "../menus/TransactionContextMenu.svelte";
    import ConfirmDialog from "../modals/ConfirmDialog.svelte";
    import MarkAsSplitModal from "../modals/MarkAsSplitModal.svelte";
    import MarkAsLoanModal from "../modals/MarkAsLoanModal.svelte";
    import LinkToEntryModal from "../modals/LinkToEntryModal.svelte";
    import ReclassifyModal from "../modals/ReclassifyModal.svelte";
    import ReimbursementsListModal from "../modals/ReimbursementsListModal.svelte";

    import TransactionDetailsModal from "../modals/TransactionDetailsModal.svelte";
    import TransactionRow from "./TransactionRow.svelte";
    import TransactionInputRow from "./TransactionInputRow.svelte";
    import ResolveCalibrationModal from "../modals/ResolveCalibrationModal.svelte";
    import MergeTransactionsModal from "../modals/MergeTransactionsModal.svelte";
    import { Funnel } from "svelte-heros-v2";
    import { showAlert, showConfirm } from "$lib/utils/dialog";

    interface Props {
        transactions: PopulatedTransaction[];
        wallets: Wallet[];
        categories: CategoryWithSubcategories[];
        subcategories: Subcategory[];
        addingNewRow: boolean;
        onUpdate: () => void;
        onDelete: () => void;
        onTransactionCreated: () => void;
        onCancelAdd: () => void;
    }

    let {
        transactions,
        wallets,
        categories,
        subcategories,
        addingNewRow,
        onUpdate,
        onDelete,
        onTransactionCreated,
        onCancelAdd,
    }: Props = $props();

    let selectedTransaction = $state<PopulatedTransaction | null>(null);
    // let contextMenuPosition = $state<{ x: number; y: number } | null>(null); // Removed, replaced by contextMenu state
    let editingCell = $state<{ id: number; field: string } | null>(null);
    let editValue = $state("");

    // Confirmation dialog state
    let showConfirmDialog = $state(false);
    let transactionToDelete = $state<PopulatedTransaction | null>(null);

    // Selection Mode State
    let selectionMode = $state(false);
    let selectedTransactions = $state<Set<number>>(new Set());

    // Modal state
    let showSplitModal = $state(false);
    let showLoanModal = $state(false);
    let showDebtModal = $state(false); // For Mark as Debt
    let showLinkModal = $state(false);
    let showReclassifyModal = $state(false);
    let showReimbursementModal = $state(false);
    let showDetailsModal = $state(false);
    let showResolveCalibrationModal = $state(false);
    let showMergeModal = $state(false);
    let transactionForModal = $state<
        PopulatedTransaction | PopulatedTransaction[] | null
    >(null);

    // ... (keep existing code)

    let contextMenu = $state<{
        visible: boolean;
        x: number;
        y: number;
        transaction: PopulatedTransaction | null;
    }>({
        visible: false,
        x: 0,
        y: 0,
        transaction: null,
    });

    const isContextMenuOpen = $derived(contextMenu.visible);

    // Filter state
    let showFilters = $state(false);
    let activeFilterColumn = $state<string | null>(null);

    // Filter values
    let dateFromFilter = $state("");
    let dateToFilter = $state("");
    let descriptionFilter = $state("");
    let selectedCategories = $state<Set<string>>(new Set()); // Changed to string to handle "cat_X" and "subcat_X"
    let amountMinFilter = $state("");
    let amountMaxFilter = $state("");
    let selectedWallets = $state<Set<number>>(new Set());
    let selectedTypes = $state<Set<Classification>>(new Set());

    // New Transaction State
    let newTransactionDate = $state(new Date().toISOString().split("T")[0]);
    let addingToDate = $state<string | null>(null);

    // Filtered transactions using $derived
    const filteredTransactions = $derived.by(() => {
        let result = transactions;

        // Date range filter
        if (dateFromFilter) {
            result = result.filter((t) => t.date >= dateFromFilter);
        }
        if (dateToFilter) {
            result = result.filter((t) => t.date <= dateToFilter);
        }

        // Description filter (case-insensitive contains)
        if (descriptionFilter.trim()) {
            const search = descriptionFilter.toLowerCase();
            result = result.filter((t) =>
                t.description.toLowerCase().includes(search),
            );
        }

        // Category filter (multi-select) - handle both categories and subcategories
        if (selectedCategories.size > 0) {
            result = result.filter((t) => {
                // Check if transaction has subcategory
                if (t.subcategory_id) {
                    return selectedCategories.has(`subcat_${t.subcategory_id}`);
                }
                // Check if transaction has category (without subcategory)
                if (t.category_id) {
                    return selectedCategories.has(`cat_${t.category_id}`);
                }
                // Check if "None" is selected
                return selectedCategories.has("none");
            });
        }

        // Amount range filter
        if (amountMinFilter) {
            const min = parseFloat(amountMinFilter);
            result = result.filter((t) => t.amount >= min);
        }
        if (amountMaxFilter) {
            const max = parseFloat(amountMaxFilter);
            result = result.filter((t) => t.amount <= max);
        }

        // Wallet filter (multi-select)
        if (selectedWallets.size > 0) {
            result = result.filter((t) => selectedWallets.has(t.wallet_id));
        }

        // Type filter (multi-select)
        if (selectedTypes.size > 0) {
            result = result.filter((t) => selectedTypes.has(t.classification));
        }

        return result;
    });

    const groupedTransactions = $derived.by(() => {
        const groups: { date: string; transactions: PopulatedTransaction[] }[] =
            [];
        let currentDate = "";
        let currentGroup: PopulatedTransaction[] = [];

        for (const t of filteredTransactions) {
            if (t.date !== currentDate) {
                if (currentDate) {
                    groups.push({
                        date: currentDate,
                        transactions: currentGroup,
                    });
                }
                currentDate = t.date;
                currentGroup = [t];
            } else {
                currentGroup.push(t);
            }
        }
        if (currentDate) {
            groups.push({ date: currentDate, transactions: currentGroup });
        }
        return groups;
    });

    function formatSectionDate(date: string): string {
        const [y, m, d] = date.split("-").map(Number);
        const dateObj = new Date(y, m - 1, d);
        const weekday = dateObj.toLocaleDateString($settings.language, {
            weekday: "short",
        });
        const dayStr = String(d).padStart(2, "0");
        return `${dayStr} (${weekday})`;
    }

    // Check if any filters are active
    const hasActiveFilters = $derived(
        dateFromFilter ||
            dateToFilter ||
            descriptionFilter ||
            selectedCategories.size > 0 ||
            amountMinFilter ||
            amountMaxFilter ||
            selectedWallets.size > 0 ||
            selectedTypes.size > 0,
    );

    function handleMarkAsDebt(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showDebtModal = true;
    }

    async function handleDelete(transaction: PopulatedTransaction) {
        // Close context menu first
        handleCloseContextMenu();

        // Show custom confirmation dialog
        transactionToDelete = transaction;
        showConfirmDialog = true;
    }

    async function handleBulkDelete() {
        if (selectedTransactions.size === 0) return;

        if (
            !(await showConfirm(
                `Are you sure you want to delete ${selectedTransactions.size} transactions?`,
                "Delete Transactions",
            ))
        ) {
            return;
        }

        try {
            await api.transactions.deleteTransactions(
                Array.from(selectedTransactions),
            );
            selectedTransactions.clear();
            selectionMode = false;
            onDelete(); // Refresh
        } catch (err) {
            console.error("Failed to delete transactions:", err);
        }
    }

    async function confirmDelete() {
        if (!transactionToDelete) return;

        showConfirmDialog = false;

        try {
            await api.transactions.delete(transactionToDelete.id);
            transactionToDelete = null;
            onDelete();
        } catch (err) {
            console.error("Failed to delete transaction:", err);
            // Alert removed to improve UX
        }
    }

    function cancelDelete() {
        showConfirmDialog = false;
        transactionToDelete = null;
    }

    function handleLinkToEntry(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showLinkModal = true;
    }

    async function handleBulkLinkToEntry() {
        const txns = transactions.filter((t) => selectedTransactions.has(t.id));
        if (txns.length === 0) return;

        // Verify all have same direction
        const direction = txns[0].direction;
        if (txns.some((t) => t.direction !== direction)) {
            await showAlert(
                "All selected transactions must have the same direction (Inflow/Outflow)",
                "Error",
            );
            return;
        }

        // Pass array of transactions to modal (modal handles array now)
        // We cast to any because modal prop type is complex, but we updated it
        transactionForModal = txns as any;
        showLinkModal = true;
    }

    async function handleUnclassify(transaction: PopulatedTransaction) {
        if (
            !(await showConfirm(
                "Are you sure you want to unclassify this transaction? This will remove all split/loan/debt details.",
                "Unclassify Transaction",
            ))
        ) {
            return;
        }
        try {
            await api.transactions.unclassify(transaction.id);
            onUpdate();
        } catch (e) {
            console.error("Failed to unclassify", e);
            // Alert removed to improve UX
        }
    }

    function handleViewDetails(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showDetailsModal = true;
    }

    async function handleIgnore(transaction: PopulatedTransaction) {
        try {
            await api.transactions.ignore(transaction.id);
            onUpdate();
        } catch (e) {
            console.error("Failed to ignore transaction", e);
        }
    }

    async function handleBulkIgnore() {
        try {
            await api.transactions.ignoreTransactions(
                Array.from(selectedTransactions),
            );
            selectedTransactions.clear();
            selectionMode = false;
            onUpdate();
        } catch (e) {
            console.error("Failed to ignore transactions", e);
        }
    }

    async function handleUnignore(transaction: PopulatedTransaction) {
        try {
            await api.transactions.unignore(transaction.id);
            onUpdate();
        } catch (e) {
            console.error("Failed to unignore transaction", e);
        }
    }

    async function handleBulkUnignore() {
        try {
            await api.transactions.unignoreTransactions(
                Array.from(selectedTransactions),
            );
            selectedTransactions.clear();
            selectionMode = false;
            onUpdate();
        } catch (e) {
            console.error("Failed to unignore transactions", e);
        }
    }

    function handleResolveCalibration(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showResolveCalibrationModal = true;
    }

    function handleReclassify(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showReclassifyModal = true;
    }

    function handleViewReimbursements(transaction: PopulatedTransaction) {
        transactionForModal = transaction;
        showReimbursementModal = true;
    }

    function handleRowClick(transaction: PopulatedTransaction) {
        if (selectionMode) {
            const newSet = new Set(selectedTransactions);
            if (newSet.has(transaction.id)) {
                newSet.delete(transaction.id);
            } else {
                newSet.add(transaction.id);
            }
            selectedTransactions = newSet;
        } else {
            selectedTransaction = transaction;
        }
    }

    function handleRowRightClick(
        event: MouseEvent,
        transaction: PopulatedTransaction,
    ) {
        event.preventDefault();

        // If in selection mode and clicking on a selected row, show bulk context menu
        if (selectionMode && selectedTransactions.has(transaction.id)) {
            contextMenu = {
                visible: true,
                x: event.clientX,
                y: event.clientY,
                transaction: transaction, // This is just a representative, context menu will check selectedTransactions
            };
            return;
        }

        // Normal right click (or clicking unselected row in selection mode -> behaves as normal single select?)
        // Let's exit selection mode if right clicking outside selection?
        // Or just show menu for that single row.
        // Current requirement: "Right click on any transaction in the selected ones (**only can rightclick on selected ones**)"

        contextMenu = {
            visible: true,
            x: event.clientX,
            y: event.clientY,
            transaction: transaction,
        };
    }

    function handleCloseContextMenu() {
        contextMenu = { ...contextMenu, visible: false, transaction: null };
    }

    function startEdit(transaction: PopulatedTransaction, field: string) {
        editingCell = { id: transaction.id, field };

        switch (field) {
            case "date":
                editValue = transaction.date;
                break;
            case "description":
                editValue = transaction.description;
                break;
            case "amount":
                editValue = transaction.amount.toString();
                break;
            case "category":
                // If has subcategory, use subcategory_id, otherwise use category_id with "cat_" prefix
                if (transaction.subcategory_id) {
                    editValue = transaction.subcategory_id.toString();
                } else if (transaction.category_id) {
                    editValue = `cat_${transaction.category_id}`;
                } else {
                    editValue = "null";
                }
                break;
            case "wallet":
                editValue = transaction.wallet_id.toString();
                break;
        }
    }

    // Filter functions
    function toggleFilterColumn(column: string) {
        if (activeFilterColumn === column) {
            activeFilterColumn = null;
        } else {
            activeFilterColumn = column;
        }
    }

    function clearAllFilters() {
        dateFromFilter = "";
        dateToFilter = "";
        descriptionFilter = "";
        selectedCategories = new Set();
        amountMinFilter = "";
        amountMaxFilter = "";
        selectedWallets = new Set();
        selectedTypes = new Set();
        activeFilterColumn = null;
    }

    function toggleCategoryFilter(categoryKey: string) {
        const newSet = new Set(selectedCategories);
        if (newSet.has(categoryKey)) {
            newSet.delete(categoryKey);
        } else {
            newSet.add(categoryKey);
        }
        selectedCategories = newSet;
    }

    function toggleWalletFilter(walletId: number) {
        const newSet = new Set(selectedWallets);
        if (newSet.has(walletId)) {
            newSet.delete(walletId);
        } else {
            newSet.add(walletId);
        }
        selectedWallets = newSet;
    }

    function toggleTypeFilter(type: Classification) {
        const newSet = new Set(selectedTypes);
        if (newSet.has(type)) {
            newSet.delete(type);
        } else {
            newSet.add(type);
        }
        selectedTypes = newSet;
    }

    // Get unique values for filters
    const uniqueCategories = $derived.by(() => {
        const items: Array<{
            key: string;
            label: string;
            isCategory: boolean;
        }> = [];

        // Add "None" option
        items.push({ key: "none", label: "None", isCategory: false });

        // Add categories and subcategories
        categories.forEach((cat) => {
            if (cat.subcategories && cat.subcategories.length > 0) {
                // Category has subcategories - add each subcategory
                cat.subcategories.forEach((subcat) => {
                    items.push({
                        key: `subcat_${subcat.id}`,
                        label: `${cat.emoji} ${cat.name} › ${subcat.name}`,
                        isCategory: false,
                    });
                });
            } else {
                // Category has no subcategories - add the category itself
                items.push({
                    key: `cat_${cat.id}`,
                    label: `${cat.emoji} ${cat.name}`,
                    isCategory: true,
                });
            }
        });

        return items;
    });

    const uniqueTypes = $derived.by(() => {
        const types = new Set<Classification>();
        transactions.forEach((t) => types.add(t.classification));
        return Array.from(types);
    });
    function handleSelectMultiple() {
        selectionMode = true;
        if (contextMenu.transaction) {
            selectedTransactions.add(contextMenu.transaction.id);
            selectedTransactions = new Set(selectedTransactions); // Trigger reactivity
        }
        handleCloseContextMenu();
    }

    async function handleMerge() {
        if (selectedTransactions.size < 2) return;

        const txns = transactions.filter((t) => selectedTransactions.has(t.id));
        if (txns.length < 2) return;

        // Validation
        const first = txns[0];
        const walletId = first.wallet_id;
        const direction = first.direction;

        const sameWallet = txns.every((t) => t.wallet_id === walletId);
        const sameDirection = txns.every((t) => t.direction === direction);

        if (!sameWallet) {
            await showAlert(
                "All transactions must belong to the same wallet",
                "Error",
            );
            return;
        }
        if (!sameDirection) {
            await showAlert(
                "All transactions must have the same direction",
                "Error",
            );
            return;
        }

        // Check for special transactions
        const hasSpecial = txns.some(
            (t) =>
                t.is_calibration ||
                !["expense", "income"].includes(t.classification),
        );

        if (hasSpecial) {
            await showAlert(
                "Cannot merge special transactions (Transfers, Splits, Loans, etc.). Only simple Expenses and Income can be merged.",
                "Error",
            );
            return;
        }

        transactionForModal = txns;
        showMergeModal = true;
    }
</script>

<div class="transaction-table-container">
    {#if selectionMode}
        <div class="table-actions">
            <span class="selection-count"
                >{selectedTransactions.size} selected</span
            >
            <button
                class="btn secondary"
                onclick={() => {
                    selectionMode = false;
                    selectedTransactions.clear();
                }}
            >
                Cancel Selection
            </button>
        </div>
    {/if}

    <table class="transaction-table">
        <thead>
            <tr>
                <!-- Date column removed -->
                <th>
                    <div class="th-content">
                        <span>{$t.common.category}</span>
                        <button
                            class="filter-btn"
                            class:active={selectedCategories.size > 0}
                            onclick={() => toggleFilterColumn("category")}
                            title="Filter category"
                        >
                            <Funnel size="12" />
                        </button>
                    </div>
                    {#if activeFilterColumn === "category"}
                        <div class="filter-dropdown">
                            {#each uniqueCategories as item}
                                <label class="filter-checkbox">
                                    <input
                                        type="checkbox"
                                        checked={selectedCategories.has(
                                            item.key,
                                        )}
                                        onchange={() =>
                                            toggleCategoryFilter(item.key)}
                                    />
                                    {item.label}
                                </label>
                            {/each}
                            <button
                                class="clear-filter-btn"
                                onclick={() => (selectedCategories = new Set())}
                            >
                                Clear
                            </button>
                        </div>
                    {/if}
                </th>
                <th>
                    <div class="th-content">
                        <span>{$t.common.description}</span>
                        <button
                            class="filter-btn"
                            class:active={descriptionFilter}
                            onclick={() => toggleFilterColumn("description")}
                            title="Filter description"
                        >
                            <Funnel size="12" />
                        </button>
                    </div>
                    {#if activeFilterColumn === "description"}
                        <div class="filter-dropdown">
                            <input
                                type="text"
                                bind:value={descriptionFilter}
                                placeholder="Search description..."
                                class="filter-search"
                            />
                            <button
                                class="clear-filter-btn"
                                onclick={() => (descriptionFilter = "")}
                            >
                                Clear
                            </button>
                        </div>
                    {/if}
                </th>
                <th>
                    <div class="th-content">
                        <span>{$t.common.amount}</span>
                        <button
                            class="filter-btn"
                            class:active={amountMinFilter || amountMaxFilter}
                            onclick={() => toggleFilterColumn("amount")}
                            title="Filter amount"
                        >
                            <Funnel size="12" />
                        </button>
                    </div>
                    {#if activeFilterColumn === "amount"}
                        <div class="filter-dropdown">
                            <div class="filter-section">
                                <label>
                                    Min:
                                    <input
                                        type="number"
                                        bind:value={amountMinFilter}
                                        placeholder="0"
                                        step="100"
                                    />
                                </label>
                            </div>
                            <div class="filter-section">
                                <label>
                                    Max:
                                    <input
                                        type="number"
                                        bind:value={amountMaxFilter}
                                        placeholder="999999"
                                        step="100"
                                    />
                                </label>
                            </div>
                            <button
                                class="clear-filter-btn"
                                onclick={() => {
                                    amountMinFilter = "";
                                    amountMaxFilter = "";
                                }}
                            >
                                Clear
                            </button>
                        </div>
                    {/if}
                </th>
                <th>
                    <div class="th-content">
                        <span>{$t.common.wallet}</span>
                        <button
                            class="filter-btn"
                            class:active={selectedWallets.size > 0}
                            onclick={() => toggleFilterColumn("wallet")}
                            title="Filter wallet"
                        >
                            <Funnel size="12" />
                        </button>
                    </div>
                    {#if activeFilterColumn === "wallet"}
                        <div class="filter-dropdown">
                            {#each wallets as wallet}
                                <label class="filter-checkbox">
                                    <input
                                        type="checkbox"
                                        checked={selectedWallets.has(wallet.id)}
                                        onchange={() =>
                                            toggleWalletFilter(wallet.id)}
                                    />
                                    {wallet.name}
                                </label>
                            {/each}
                            <button
                                class="clear-filter-btn"
                                onclick={() => (selectedWallets = new Set())}
                            >
                                Clear
                            </button>
                        </div>
                    {/if}
                </th>
                <th>
                    <div class="th-content">
                        <span>{$t.common.type}</span>
                        <button
                            class="filter-btn"
                            class:active={selectedTypes.size > 0}
                            onclick={() => toggleFilterColumn("type")}
                            title="Filter type"
                        >
                            <Funnel size="12" />
                        </button>
                    </div>
                    {#if activeFilterColumn === "type"}
                        <div class="filter-dropdown">
                            {#each uniqueTypes as type}
                                <label class="filter-checkbox">
                                    <input
                                        type="checkbox"
                                        checked={selectedTypes.has(type)}
                                        onchange={() => toggleTypeFilter(type)}
                                    />
                                    {type.replace("_", " ")}
                                </label>
                            {/each}
                            <button
                                class="clear-filter-btn"
                                onclick={() => (selectedTypes = new Set())}
                            >
                                Clear
                            </button>
                        </div>
                    {/if}
                </th>
            </tr>
        </thead>
        <tbody>
            {#if addingNewRow}
                <tr class="date-input-row">
                    <td colspan="5">
                        <div class="date-input-wrapper">
                            <span>{$t.common.date}:</span>
                            <input
                                type="date"
                                bind:value={newTransactionDate}
                            />
                        </div>
                    </td>
                </tr>
                <TransactionInputRow
                    {wallets}
                    {categories}
                    {subcategories}
                    date={newTransactionDate}
                    onDateChange={(d) => (newTransactionDate = d)}
                    onSave={() => {
                        onTransactionCreated();
                    }}
                    onCancel={onCancelAdd}
                />
            {/if}

            {#each groupedTransactions as group}
                <tr
                    class="date-section-row"
                    onclick={() => (addingToDate = group.date)}
                    role="button"
                    tabindex="0"
                    title={$t.transactions.addTransactionForDate}
                >
                    <td colspan="5">{formatSectionDate(group.date)}</td>
                </tr>

                {#if addingToDate === group.date}
                    <TransactionInputRow
                        {wallets}
                        {categories}
                        {subcategories}
                        date={group.date}
                        onDateChange={(d) => (addingToDate = d)}
                        onSave={() => {
                            onTransactionCreated();
                            addingToDate = null;
                        }}
                        onCancel={() => (addingToDate = null)}
                    />
                {/if}

                {#each group.transactions as transaction (transaction.id)}
                    <TransactionRow
                        {transaction}
                        isSelected={selectionMode
                            ? selectedTransactions.has(transaction.id)
                            : selectedTransaction?.id === transaction.id}
                        isSelectionMode={selectionMode}
                        editingField={editingCell?.id === transaction.id
                            ? editingCell.field
                            : null}
                        {wallets}
                        {categories}
                        {subcategories}
                        onSelect={() => handleRowClick(transaction)}
                        onContextMenu={(e: MouseEvent) =>
                            handleRowRightClick(e, transaction)}
                        onEditStart={(field: string) =>
                            startEdit(transaction, field)}
                        onEditEnd={() => (editingCell = null)}
                        {onUpdate}
                    />
                {/each}
            {/each}

            {#if filteredTransactions.length === 0 && !addingNewRow}
                <tr>
                    <td colspan="5" class="empty-list-message">
                        {#if hasActiveFilters}
                            {$t.transactions.noMatches}
                            <button
                                class="btn primary"
                                onclick={clearAllFilters}
                                style="margin-top: 12px; display: inline-block;"
                            >
                                {$t.transactions.clearFilters}
                            </button>
                        {:else}
                            {$t.transactions.noTransactions}
                        {/if}
                    </td>
                </tr>
            {/if}
        </tbody>
    </table>

    <div class="list-footer">
        <p>{$t.transactions.endOfList}</p>
    </div>
</div>

{#if contextMenu.visible && contextMenu.transaction}
    <TransactionContextMenu
        transaction={contextMenu.transaction}
        multipleSelected={selectedTransactions.size > 0}
        position={{ x: contextMenu.x, y: contextMenu.y }}
        onClose={handleCloseContextMenu}
        onDelete={() =>
            contextMenu.transaction
                ? handleDelete(contextMenu.transaction)
                : null}
        {onUpdate}
        onMarkAsSplit={() =>
            contextMenu.transaction
                ? (transactionForModal = contextMenu.transaction) &&
                  (showSplitModal = true)
                : null}
        onMarkAsLoan={() =>
            contextMenu.transaction
                ? (transactionForModal = contextMenu.transaction) &&
                  (showLoanModal = true)
                : null}
        onMarkAsDebt={() =>
            contextMenu.transaction
                ? handleMarkAsDebt(contextMenu.transaction)
                : null}
        onLinkToEntry={() =>
            contextMenu.transaction
                ? handleLinkToEntry(contextMenu.transaction)
                : null}
        onUnclassify={() =>
            contextMenu.transaction
                ? handleUnclassify(contextMenu.transaction)
                : null}
        onViewDetails={() =>
            contextMenu.transaction
                ? handleViewDetails(contextMenu.transaction)
                : null}
        onReclassify={() =>
            contextMenu.transaction
                ? handleReclassify(contextMenu.transaction)
                : null}
        onViewReimbursements={() =>
            contextMenu.transaction
                ? handleViewReimbursements(contextMenu.transaction)
                : null}
        onIgnore={() =>
            contextMenu.transaction
                ? handleIgnore(contextMenu.transaction)
                : null}
        onUnignore={() =>
            contextMenu.transaction
                ? handleUnignore(contextMenu.transaction)
                : null}
        onResolveCalibration={() =>
            contextMenu.transaction
                ? handleResolveCalibration(contextMenu.transaction)
                : null}
        onSelectMultiple={handleSelectMultiple}
        onMerge={handleMerge}
    />
{/if}

{#if showConfirmDialog}
    <ConfirmDialog
        message="Are you sure you want to delete this transaction?"
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
    />
{/if}

{#if showSplitModal && transactionForModal && !Array.isArray(transactionForModal)}
    <MarkAsSplitModal
        transaction={transactionForModal}
        onClose={() => {
            showSplitModal = false;
            transactionForModal = null;
        }}
        onSave={() => {
            showSplitModal = false;
            transactionForModal = null;
            onUpdate();
        }}
    />
{/if}

{#if showLoanModal && transactionForModal && !Array.isArray(transactionForModal)}
    <MarkAsLoanModal
        transaction={transactionForModal}
        isDebt={false}
        onClose={() => {
            showLoanModal = false;
            transactionForModal = null;
        }}
        onSave={() => {
            showLoanModal = false;
            transactionForModal = null;
            onUpdate();
        }}
    />
{/if}

{#if showDebtModal && transactionForModal && !Array.isArray(transactionForModal)}
    <MarkAsLoanModal
        transaction={transactionForModal}
        isDebt={true}
        onClose={() => {
            showDebtModal = false;
            transactionForModal = null;
        }}
        onSave={() => {
            showDebtModal = false;
            transactionForModal = null;
            onUpdate();
        }}
    />
{/if}

{#if showResolveCalibrationModal && transactionForModal && !Array.isArray(transactionForModal)}
    <ResolveCalibrationModal
        calibration={transactionForModal}
        {categories}
        {wallets}
        onClose={() => {
            showResolveCalibrationModal = false;
            transactionForModal = null;
        }}
        onSuccess={() => {
            showResolveCalibrationModal = false;
            transactionForModal = null;
            // Full refresh needed as original transaction might be deleted or updated
            onUpdate();
        }}
    />
{/if}

{#if showLinkModal && transactionForModal}
    <LinkToEntryModal
        transaction={transactionForModal}
        onClose={() => {
            showLinkModal = false;
            transactionForModal = null;
        }}
        onSave={() => {
            showLinkModal = false;
            transactionForModal = null;
            onUpdate();
        }}
    />
{/if}

{#if showReclassifyModal && transactionForModal && !Array.isArray(transactionForModal)}
    <ReclassifyModal
        transaction={transactionForModal}
        onClose={() => {
            showReclassifyModal = false;
            transactionForModal = null;
        }}
        onSave={(newClassification) => {
            showReclassifyModal = false;
            onUpdate();

            // Auto-open Mark as Debt/Loan if applicable
            if (newClassification === "borrow") {
                showDebtModal = true;
                // keep transactionForModal
            } else if (newClassification === "lend") {
                showLoanModal = true;
                // keep transactionForModal
            } else {
                transactionForModal = null;
            }
        }}
    />
{/if}

{#if showReimbursementModal && transactionForModal && !Array.isArray(transactionForModal)}
    <ReimbursementsListModal
        transaction={transactionForModal}
        onClose={() => {
            showReimbursementModal = false;
            transactionForModal = null;
        }}
    />
{/if}

{#if showDetailsModal && transactionForModal && !Array.isArray(transactionForModal)}
    <TransactionDetailsModal
        transaction={transactionForModal}
        {wallets}
        {categories}
        {subcategories}
        onClose={() => {
            showDetailsModal = false;
            transactionForModal = null;
        }}
        {onUpdate}
    />
{/if}

{#if showMergeModal && transactionForModal && Array.isArray(transactionForModal)}
    <MergeTransactionsModal
        transactions={transactionForModal}
        {categories}
        {subcategories}
        {wallets}
        onClose={() => {
            showMergeModal = false;
            transactionForModal = null;
        }}
        onSave={() => {
            showMergeModal = false;
            transactionForModal = null;
            selectedTransactions.clear();
            selectionMode = false;
            onUpdate();
        }}
    />
{/if}

<style>
    .list-footer {
        padding: 4rem 0;
        text-align: center;
        color: var(--text-tertiary);
        font-size: 0.875rem;
    }
</style>
