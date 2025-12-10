<script lang="ts">
    import { onMount } from "svelte";
    import { fade, slide } from "svelte/transition";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type {
        Wallet,
        PopulatedTransaction,
        CategoryWithSubcategories,
        LinkedEntry,
    } from "$lib/api/types";
    import Modal from "$lib/components/modals/Modal.svelte";
    import CalibrateWalletModal from "$lib/components/modals/CalibrateWalletModal.svelte";
    import WalletContextMenu from "$lib/components/menus/WalletContextMenu.svelte";
    import WalletModal from "$lib/components/modals/WalletModal.svelte";
    import TransferModal from "$lib/components/modals/TransferModal.svelte";
    import { showAlert, showConfirm } from "$lib/utils/dialog";

    let wallets: Wallet[] = $state([]);
    let allTransfers: PopulatedTransaction[] = $state([]);
    let categories: CategoryWithSubcategories[] = $state([]);
    let loading = $state(true);

    // Summary stats
    let totalAvailable = $state(0);
    let totalCreditUsed = $state(0);
    let netPosition = $state(0);
    let pendingDebts = $state(0);
    let selectedWalletId = $state<number | null>(null);

    // Modal State
    let showWalletModal = $state(false);
    let showCalibrateModal = $state(false);
    let walletToCalibrate = $state<Wallet | null>(null);
    let walletToEdit = $state<Wallet | null>(null);
    let showTransferModal = $state(false);
    let sourceWalletForTransfer = $state<number | undefined>(undefined);

    // Context Menu State
    let contextMenu = $state<{
        visible: boolean;
        x: number;
        y: number;
        wallet: Wallet | null;
    }>({
        visible: false,
        x: 0,
        y: 0,
        wallet: null,
    });

    // Form State

    onMount(async () => {
        await loadData();
    });

    async function loadData() {
        loading = true;
        try {
            wallets = await api.wallets.getAll();

            // Default emoji for wallets if missing
            wallets = wallets.map((w) => ({
                ...w,
                emoji: w.emoji || (w.wallet_type === "credit" ? "💳" : "💰"),
            }));

            let pendingEntries: LinkedEntry[] = [];
            [categories, allTransfers, pendingEntries] = await Promise.all([
                api.categories.getAll(),
                api.transactions.list({
                    classification: "transfer",
                    limit: 20,
                }),
                api.linkedEntries.getPending(),
            ]);

            // Calculate pending debts
            pendingDebts = pendingEntries
                .filter((e) => e.link_type === "debt")
                .reduce((sum, e) => sum + (Number(e.pending_amount) || 0), 0);

            calculateStats();
        } catch (error) {
            console.error("Failed to load wallet data:", error);
        } finally {
            loading = false;
        }
    }

    function calculateStats() {
        let available = 0;
        let creditUsed = 0;

        for (const w of wallets) {
            if (w.wallet_type === "normal") {
                available += Number(w.current_balance);
            } else if (w.wallet_type === "credit") {
                creditUsed += Number(w.current_balance);
                if (w.available_credit !== undefined) {
                    available += Number(w.available_credit);
                }
            }
        }

        totalAvailable = available;
        totalCreditUsed = creditUsed;
        netPosition = totalAvailable - totalCreditUsed - pendingDebts;
    }

    function formatCurrency(amount: number): string {
        return (
            "¥" +
            new Intl.NumberFormat("en-US", {
                style: "decimal",
                minimumFractionDigits: 0,
                maximumFractionDigits: 0,
            }).format(amount)
        );
    }

    function formatDate(dateStr: string): string {
        if (!dateStr) return "";
        const d = new Date(dateStr);
        return `${d.getMonth() + 1}/${d.getDate()}`;
    }

    function getWalletTransfers(
        walletId: number | null,
    ): PopulatedTransaction[] {
        if (!walletId) {
            return allTransfers.slice(0, 20);
        }
        return allTransfers
            .filter((t) => t.wallet_id === walletId)
            .slice(0, 20);
    }

    function selectWallet(id: number) {
        if (selectedWalletId === id) {
            selectedWalletId = null;
        } else {
            selectedWalletId = id;
        }
    }

    // --- Wallet Actions ---

    function openAddModal() {
        walletToEdit = null;
        showWalletModal = true;
    }

    function openEditModal(e: Event, wallet: Wallet) {
        e.stopPropagation();
        walletToEdit = wallet;
        showWalletModal = true;
    }

    async function deleteWallet() {
        if (!contextMenu.wallet) return;
        const wallet = contextMenu.wallet;
        closeContextMenu();

        if (
            !(await showConfirm(
                `Are you sure you want to delete ${wallet.name}?`,
                "Delete Wallet",
            ))
        )
            return;

        try {
            await api.wallets.delete(wallet.id);
            if (selectedWalletId === wallet.id) selectedWalletId = null;
            await loadData();
        } catch (error) {
            console.error("Failed to delete wallet:", error);
        }
    }

    function handleContextMenu(event: MouseEvent, wallet: Wallet) {
        event.preventDefault();
        contextMenu = {
            visible: true,
            x: event.clientX,
            y: event.clientY,
            wallet,
        };
    }

    function closeContextMenu() {
        contextMenu.visible = false;
        contextMenu.wallet = null;
    }

    function handleEditFromMenu() {
        if (contextMenu.wallet) {
            const w = contextMenu.wallet;
            closeContextMenu();
            // Mock event for openEditModal which expects one
            openEditModal({ stopPropagation: () => {} } as any, w);
        }
    }

    function handleCalibrateFromMenu() {
        if (contextMenu.wallet) {
            const w = contextMenu.wallet;
            closeContextMenu();
            walletToCalibrate = w;
            showCalibrateModal = true;
        }
    }

    function handleTransferFromMenu() {
        if (contextMenu.wallet) {
            sourceWalletForTransfer = contextMenu.wallet.id;
            closeContextMenu();
            showTransferModal = true;
        }
    }
</script>

<div class="mac-layout">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.wallets.title}</h1>
            <button class="add-btn" onclick={openAddModal}
                >+ {$t.wallets.addWallet}</button
            >
        </div>
    </header>

    <div class="pane-content padded">
        <div class="content-wrapper">
            <!-- 1. Summary Section -->
            <section class="summary-section">
                <!-- ... (Summary cards remain same) -->
                <div class="summary-card">
                    <span class="label">{$t.wallets.availableCredit}</span>
                    <span class="value">{formatCurrency(totalAvailable)}</span>
                </div>
                <div class="summary-card">
                    <span class="label">{$t.wallets.creditUsed}</span>
                    <span class="value debt"
                        >{formatCurrency(totalCreditUsed)}</span
                    >
                </div>
                <div class="summary-card" title={$t.wallets.netPositionTooltip}>
                    <span class="label">{$t.wallets.netPosition}</span>
                    <span
                        class="value"
                        class:positive={netPosition >= 0}
                        class:negative={netPosition < 0}
                    >
                        {formatCurrency(netPosition)}
                    </span>
                    {#if pendingDebts > 0}
                        <span class="sub-text debt-sub"
                            >(- {formatCurrency(pendingDebts)} debts)</span
                        >
                    {/if}
                </div>
            </section>

            <!-- 2. Wallet List -->
            <h2 class="section-title">{$t.wallets.walletList}</h2>
            <section class="wallet-grid">
                {#if loading}
                    <div class="loading">{$t.common.loading}</div>
                {:else}
                    {#each wallets as wallet (wallet.id)}
                        <!-- svelte-ignore a11y_click_events_have_key_events -->
                        <div
                            class="wallet-card"
                            class:selected={selectedWalletId === wallet.id}
                            onclick={() => selectWallet(wallet.id)}
                            oncontextmenu={(e) => handleContextMenu(e, wallet)}
                            role="button"
                            tabindex="0"
                            in:slide
                        >
                            <div class="card-top">
                                <div class="wallet-icon">
                                    <span
                                        >{wallet.emoji ||
                                            (wallet.wallet_type === "credit"
                                                ? "💳"
                                                : "💰")}</span
                                    >
                                </div>
                                <div class="wallet-header-info">
                                    <h3 class="wallet-name">{wallet.name}</h3>
                                    <span
                                        class="wallet-type-badge {wallet.wallet_type}"
                                    >
                                        {$t.wallets[wallet.wallet_type]}
                                    </span>
                                </div>
                            </div>

                            <div class="wallet-balance-section">
                                {#if wallet.wallet_type === "normal"}
                                    <span class="main-balance"
                                        >{formatCurrency(
                                            wallet.current_balance,
                                        )}</span
                                    >
                                {:else}
                                    <span class="main-balance debt"
                                        >{formatCurrency(
                                            wallet.current_balance,
                                        )}
                                        <span class="currency-label"
                                            >{$t.wallets.used}</span
                                        ></span
                                    >
                                    <div class="credit-details">
                                        <span class="sub-text"
                                            >{$t.wallets.remaining}: {formatCurrency(
                                                wallet.available_credit || 0,
                                            )}</span
                                        >
                                        <span class="sub-text limit"
                                            >({$t.wallets.limit}: {formatCurrency(
                                                wallet.credit_limit,
                                            )})</span
                                        >
                                    </div>
                                {/if}
                            </div>
                        </div>
                    {/each}
                {/if}
            </section>

            <!-- 3. Transfer History (Dynamic) -->
            <section class="history-section">
                <h2 class="section-title">
                    {#if selectedWalletId}
                        {$t.wallets.transfers}: {wallets.find(
                            (w) => w.id === selectedWalletId,
                        )?.name}
                    {:else}
                        {$t.wallets.recentTransfersAll}
                    {/if}
                </h2>

                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>From/To</th>
                                <th>Type</th>
                                <th class="text-right">Amount</th>
                            </tr>
                        </thead>
                        <tbody>
                            {#each getWalletTransfers(selectedWalletId) as transfer}
                                <tr class="transaction-row" in:slide>
                                    <td>
                                        <span class="date"
                                            >{formatDate(transfer.date)}</span
                                        >
                                    </td>
                                    <td>
                                        <span class="wallet-tag"
                                            >{wallets.find(
                                                (w) =>
                                                    w.id === transfer.wallet_id,
                                            )?.name || "Unknown"}</span
                                        >
                                    </td>
                                    <td>
                                        <div class="transfer-type">
                                            <span class="arrow"
                                                >{transfer.direction ===
                                                "outflow"
                                                    ? "→"
                                                    : "←"}</span
                                            >
                                            <span class="desc">
                                                {#if transfer.direction === "outflow"}
                                                    {$t.wallets.transferOut}
                                                {:else}
                                                    {$t.wallets.transferIn}
                                                {/if}
                                            </span>
                                        </div>
                                    </td>
                                    <td class="text-right">
                                        <span
                                            class="amount"
                                            class:inflow={transfer.direction ===
                                                "inflow"}
                                            class:outflow={transfer.direction ===
                                                "outflow"}
                                        >
                                            {transfer.direction === "outflow"
                                                ? "-"
                                                : "+"}{formatCurrency(
                                                transfer.amount,
                                            )}
                                        </span>
                                    </td>
                                </tr>
                            {:else}
                                <tr>
                                    <td colspan="4" class="empty-state"
                                        >{$t.wallets.noTransfers}</td
                                    >
                                </tr>
                            {/each}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    </div>

    {#if showCalibrateModal && walletToCalibrate}
        <CalibrateWalletModal
            wallet={walletToCalibrate}
            currentBalance={walletToCalibrate.current_balance}
            miscCategoryId={categories.find((c) => c.name === "Miscellaneous")
                ?.id || 0}
            onClose={() => (showCalibrateModal = false)}
            onSuccess={loadData}
        />
    {/if}

    <!-- Wallet Modal -->
    {#if showWalletModal}
        <WalletModal
            wallet={walletToEdit}
            onClose={() => (showWalletModal = false)}
            onSave={loadData}
        />
    {/if}

    {#if showTransferModal}
        <TransferModal
            {wallets}
            fromWalletId={sourceWalletForTransfer}
            onClose={() => (showTransferModal = false)}
            onSave={() => {
                showTransferModal = false;
                loadData();
            }}
        />
    {/if}

    {#if contextMenu.visible && contextMenu.wallet}
        <WalletContextMenu
            wallet={contextMenu.wallet}
            position={{ x: contextMenu.x, y: contextMenu.y }}
            onClose={closeContextMenu}
            onEdit={handleEditFromMenu}
            onDelete={deleteWallet}
            onCalibrate={handleCalibrateFromMenu}
            onTransfer={handleTransferFromMenu}
        />
    {/if}
</div>

<style>
    .mac-layout {
        background-color: var(--background);
    }

    .debt-sub {
        font-size: 12px;
        color: var(--text-tertiary);
        font-weight: normal;
    }

    .content-wrapper {
        max-width: 1200px;
        margin: 0 auto;
        padding-bottom: var(--space-8);
    }

    .add-btn {
        margin-left: auto;
    }

    /* Section Titles */
    .section-title {
        font-size: var(--font-size-lg);
        font-weight: var(--font-weight-bold);
        color: var(--text-primary);
        margin: var(--space-8) 0 var(--space-4) 0;
    }

    /* Summary Section */
    .summary-section {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-4);
        margin-bottom: var(--space-6);
    }

    .summary-card {
        background: var(--surface);
        padding: var(--space-4);
        border-radius: var(--radius-lg);
        box-shadow: var(--shadow-sm);
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
        border: 1px solid var(--border-light);
    }

    .summary-card .label {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        font-weight: var(--font-weight-medium);
    }

    .summary-card .value {
        font-size: var(--font-size-2xl);
        font-weight: var(--font-weight-bold);
    }

    .value.debt,
    .value.negative {
        color: var(--outflow);
    }
    .value.positive {
        color: var(--inflow);
    }

    /* Wallet Grid */
    .wallet-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: var(--space-4);
        margin-bottom: var(--space-8);
    }

    .wallet-card {
        background: var(--surface);
        border-radius: var(--radius-lg);
        box-shadow: var(--shadow-sm);
        padding: var(--space-4);
        transition: all 0.2s;
        cursor: pointer;
        border: 2px solid transparent;
        display: flex;
        flex-direction: column;
        gap: var(--space-4);
        position: relative;
    }

    .wallet-card:hover {
        transform: translateY(-2px);
        box-shadow: var(--shadow-md);
        border-color: var(--border-light);
    }

    .wallet-card.selected {
        border-color: var(--primary);
        background-color: var(--surface-elevated);
    }

    .card-top {
        display: flex;
        gap: var(--space-3);
        align-items: center;
    }

    .wallet-icon {
        width: 40px;
        height: 40px;
        background: var(--background);
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 20px;
        flex-shrink: 0;
    }

    .wallet-header-info {
        display: flex;
        flex-direction: column;
    }

    .wallet-name {
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-bold);
        margin: 0;
        line-height: 1.2;
    }

    .wallet-type-badge {
        font-size: 10px;
        text-transform: uppercase;
        padding: 2px 6px;
        border-radius: 4px;
        font-weight: 600;
        margin-top: 4px;
        display: inline-block;
        align-self: flex-start;
    }

    .wallet-type-badge.normal {
        background: rgba(0, 122, 255, 0.1);
        color: var(--primary);
    }
    .wallet-type-badge.credit {
        background: rgba(255, 149, 0, 0.1);
        color: var(--warning);
    }

    .wallet-balance-section {
        flex: 1;
        display: flex;
        flex-direction: column;
        justify-content: center;
    }

    .main-balance {
        font-size: var(--font-size-2xl);
        font-weight: var(--font-weight-bold);
        line-height: 1;
    }

    .main-balance.debt {
        color: var(--outflow);
    }

    .currency-label {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        font-weight: normal;
        margin-left: 4px;
    }

    .credit-details {
        display: flex;
        flex-direction: column;
        font-size: var(--font-size-xs);
        color: var(--text-secondary);
        margin-top: var(--space-2);
    }

    /* .card-actions removed */

    /* History Section */
    .table-container {
        background: var(--surface);
        border-radius: var(--radius-lg);
        overflow: hidden;
        border: 1px solid var(--border-light);
    }

    table {
        width: 100%;
        border-collapse: collapse;
    }

    th,
    td {
        padding: var(--space-3) var(--space-4);
        text-align: left;
        border-bottom: 1px solid var(--border-light);
    }

    th {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        font-weight: var(--font-weight-medium);
        background-color: var(--background);
    }

    .transaction-row:last-child td {
        border-bottom: none;
    }

    .date {
        font-size: var(--font-size-xs);
        color: var(--text-tertiary);
    }

    .wallet-tag {
        font-weight: var(--font-weight-medium);
        font-size: var(--font-size-sm);
    }

    .transfer-type {
        display: flex;
        align-items: center;
        gap: var(--space-2);
    }

    .arrow {
        font-size: var(--font-size-base);
        color: var(--text-secondary);
    }

    .desc {
        font-size: var(--font-size-sm);
        color: var(--text-primary);
    }

    .text-right {
        text-align: right;
    }

    .amount {
        font-weight: var(--font-weight-medium);
    }
    .amount.inflow {
        color: var(--inflow);
    }
    .amount.outflow {
        color: var(--outflow);
    }

    .empty-state {
        padding: var(--space-8);
        text-align: center;
        color: var(--text-tertiary);
        font-style: italic;
    }

    /* Modal Styles (kept similar) */
</style>
