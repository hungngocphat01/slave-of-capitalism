<script lang="ts">
    import { onMount } from "svelte";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type {
        PopulatedTransaction,
        Wallet,
        CategoryWithSubcategories,
        Subcategory,
    } from "$lib/api/types";
    import TransactionTable from "$lib/components/tables/TransactionTable.svelte";
    import TransferModal from "$lib/components/modals/TransferModal.svelte";

    let currentYear = $state(new Date().getFullYear());
    let currentMonth = $state(new Date().getMonth() + 1);
    let transactions = $state<PopulatedTransaction[]>([]);
    let wallets = $state<Wallet[]>([]);
    let categories = $state<CategoryWithSubcategories[]>([]);
    let subcategories = $state<Subcategory[]>([]);
    let loading = $state(true);
    let error = $state<string | null>(null);
    let addingNewRow = $state(false);
    let showTransferModal = $state(false);

    function getMonthName(month: number): string {
        const monthKeys = [
            "january",
            "february",
            "march",
            "april",
            "may",
            "june",
            "july",
            "august",
            "september",
            "october",
            "november",
            "december",
        ];
        return $t.months[monthKeys[month - 1] as keyof typeof $t.months];
    }

    async function loadData(showLoading = true) {
        if (showLoading) {
            loading = true;
        }
        error = null;

        try {
            // Load all data in parallel
            const [transactionsData, walletsData, categoriesData] =
                await Promise.all([
                    api.transactions.getByMonth(currentYear, currentMonth),
                    api.wallets.getAll(),
                    api.categories.getAll(),
                ]);

            transactions = transactionsData;
            wallets = walletsData;
            categories = categoriesData;

            console.log("Loaded transactions:", transactions);
            console.log("First transaction:", transactions[0]);

            // Extract all subcategories from categories
            subcategories = categories.flatMap(
                (cat) => cat.subcategories || [],
            );
        } catch (err) {
            error = err instanceof Error ? err.message : "Failed to load data";
            console.error("Error loading data:", err);
        } finally {
            if (showLoading) {
                loading = false;
            }
        }
    }

    function previousMonth() {
        if (currentMonth === 1) {
            currentMonth = 12;
            currentYear--;
        } else {
            currentMonth--;
        }
        loadData();
    }

    function nextMonth() {
        if (currentMonth === 12) {
            currentMonth = 1;
            currentYear++;
        } else {
            currentMonth++;
        }
        loadData();
    }

    function handleAddTransaction() {
        addingNewRow = true;
    }

    function handleCancelAdd() {
        addingNewRow = false;
    }

    function handleTransactionCreated() {
        addingNewRow = false;
        loadData(false);
    }

    onMount(() => {
        loadData();
    });
</script>

<div class="entry-screen">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.nav.entry}</h1>

            <div class="month-selector">
                <button
                    class="month-nav-btn"
                    onclick={previousMonth}
                    disabled={loading}
                    aria-label="Previous month"
                >
                    ◀
                </button>

                <div class="month-display">
                    {getMonthName(currentMonth)}
                    {currentYear}
                </div>

                <button
                    class="month-nav-btn"
                    onclick={nextMonth}
                    disabled={loading}
                    aria-label="Next month"
                >
                    ▶
                </button>
            </div>

            <div class="action-buttons">
                <button
                    class="secondary add-btn"
                    onclick={() => (showTransferModal = true)}
                    disabled={loading || addingNewRow}
                >
                    ⇄ {$t.wallets.transfer}
                </button>
                <button
                    class="add-btn"
                    onclick={handleAddTransaction}
                    disabled={loading || addingNewRow}
                >
                    + {$t.transactions.addTransaction}
                </button>
            </div>
        </div>
    </header>

    {#if showTransferModal}
        <TransferModal
            {wallets}
            onClose={() => (showTransferModal = false)}
            onSave={() => {
                showTransferModal = false;
                loadData(false);
            }}
        />
    {/if}

    <div class="screen-content">
        {#if loading}
            <div class="loading-state">
                <div class="spinner"></div>
                <p>{$t.common.loading}</p>
            </div>
        {:else if error}
            <div class="error-state">
                <p class="error-message">❌ {error}</p>
                <button class="btn primary" onclick={() => loadData(true)}
                    >{$t.common.confirm}</button
                >
            </div>
        {:else}
            <TransactionTable
                {transactions}
                {wallets}
                {categories}
                {subcategories}
                {addingNewRow}
                onUpdate={() => loadData(false)}
                onDelete={() => loadData(false)}
                onTransactionCreated={handleTransactionCreated}
                onCancelAdd={handleCancelAdd}
            />
        {/if}
    </div>
</div>

<style>
    .entry-screen {
        display: flex;
        flex-direction: column;
        height: 100%;
        overflow: hidden;
    }

    /* Header Specifics */

    /* Header Specifics */
    /* .header-content moved to global panes.css */

    /* .month-selector, .month-nav-btn, .month-display moved to global panes.css */

    .screen-content {
        flex: 1;
        overflow: hidden;
        position: relative;
    }

    .error-message {
        color: var(--error);
        font-size: var(--font-size-lg);
        margin: 0;
    }

    .action-buttons {
        display: flex;
        gap: var(--space-3);
    }
</style>
