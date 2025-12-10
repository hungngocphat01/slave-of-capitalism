<script lang="ts">
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type {
        PopulatedTransaction,
        CategoryWithSubcategories,
        Subcategory,
        Wallet,
    } from "$lib/api/types";
    import Modal from "./Modal.svelte";

    interface Props {
        transactions: PopulatedTransaction[];
        categories: CategoryWithSubcategories[];
        subcategories: Subcategory[];
        wallets: Wallet[];
        onClose: () => void;
        onSave: () => void;
    }

    let {
        transactions,
        categories,
        subcategories,
        wallets,
        onClose,
        onSave,
    }: Props = $props();

    // Initialize form with first transaction's data
    const firstTxn = transactions[0];
    let date = $state(new Date().toISOString().split("T")[0]); // Default to today as per spec "Choose a new date"
    let description = $state(firstTxn.description || "");
    let category_id = $state<number | null>(firstTxn.category_id || null);
    let subcategory_id = $state<number | null>(firstTxn.subcategory_id || null);

    // Computed
    const totalAmount = $derived(
        transactions.reduce((acc, t) => acc + Number(t.amount), 0),
    );
    const walletName = $derived(
        firstTxn.wallet?.name ||
            wallets.find((w) => w.id === firstTxn.wallet_id)?.name ||
            "",
    );
    const direction = $derived(firstTxn.direction);

    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleSubmit() {
        if (!date) {
            error = "Date is required";
            return;
        }

        saving = true;
        error = null;

        try {
            await api.transactions.merge({
                transaction_ids: transactions.map((t) => t.id),
                date,
                description,
                category_id: category_id,
                subcategory_id: subcategory_id,
            });
            onSave();
        } catch (err) {
            console.error(err);
            error = "Failed to merge transactions";
        } finally {
            saving = false;
        }
    }
</script>

<Modal title={$t.transactions.mergeTitle} {onClose}>
    <form
        id="merge-form"
        class="modal-form"
        onsubmit={(e) => {
            e.preventDefault();
            handleSubmit();
        }}
    >
        {#if error}
            <div class="error-banner">{error}</div>
        {/if}

        <div class="info-row total-row">
            <span class="label">{$t.common.total}:</span>
            <span class="value total-amount"
                >¥{totalAmount.toLocaleString()}</span
            >
        </div>
        <div class="info-row">
            <span class="label">{$t.common.wallet}:</span>
            <span class="value">{walletName}</span>
        </div>
        <div class="info-row">
            <span class="label">{$t.common.type}:</span>
            <span class="value" style="text-transform: capitalize;"
                >{direction}</span
            >
        </div>

        <div class="form-group">
            <label for="date">{$t.common.date}</label>
            <input type="date" id="date" bind:value={date} required />
        </div>

        <div class="form-group">
            <label for="description">{$t.common.description}</label>
            <input
                type="text"
                id="description"
                bind:value={description}
                required
            />
        </div>

        <div class="form-group">
            <label for="category">{$t.common.category}</label>
            <select
                id="category"
                value={subcategory_id ||
                    (category_id ? `cat_${category_id}` : "")}
                onchange={(e) => {
                    const value = (e.target as HTMLSelectElement).value;
                    if (!value || value === "") {
                        category_id = null;
                        subcategory_id = null;
                    } else if (value.startsWith("cat_")) {
                        category_id = parseInt(value.replace("cat_", ""));
                        subcategory_id = null;
                    } else {
                        const subcatId = parseInt(value);
                        const subcat = subcategories.find(
                            (s) => s.id === subcatId,
                        );
                        subcategory_id = subcatId;
                        category_id = subcat?.category_id || null;
                    }
                }}
            >
                <option value="">{$t.transactions.uncategorized}</option>
                {#each categories as category}
                    {#if category.subcategories && category.subcategories.length > 0}
                        <optgroup label="{category.emoji} {category.name}">
                            {#each category.subcategories as subcategory}
                                <option value={subcategory.id}>
                                    {subcategory.name}
                                </option>
                            {/each}
                        </optgroup>
                    {:else}
                        <option value={`cat_${category.id}`}>
                            {category.emoji}
                            {category.name}
                        </option>
                    {/if}
                {/each}
            </select>
        </div>
    </form>

    {#snippet footer()}
        <button
            class="btn mac-btn secondary"
            onclick={onClose}
            disabled={saving}
        >
            {$t.common.cancel}
        </button>
        <button
            class="btn mac-btn primary"
            type="submit"
            form="merge-form"
            disabled={saving}
        >
            {saving ? $t.common.loading : $t.common.save}
        </button>
    {/snippet}
</Modal>

<style>
    .info-row {
        display: flex;
        justify-content: space-between;
        margin-bottom: var(--space-2);
        font-size: var(--font-size-sm);
    }
    .label {
        color: var(--text-secondary);
    }
    .value {
        font-weight: 600;
        color: var(--text-primary);
    }

    .total-row {
        margin-bottom: var(--space-4);
        border-bottom: 2px solid var(--border-light);
        padding-bottom: var(--space-2);
        align-items: center;
    }
    .total-amount {
        font-size: var(--font-size-2xl);
        font-weight: 700;
        color: var(--primary);
    }
</style>
