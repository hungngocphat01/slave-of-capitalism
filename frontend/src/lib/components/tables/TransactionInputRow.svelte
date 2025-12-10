<script lang="ts">
    import { api } from "$lib/api/client";
    import type {
        Wallet,
        CategoryWithSubcategories,
        Subcategory,
        Direction,
        Classification,
    } from "$lib/api/types";

    import { t } from "$lib/i18n";

    interface Props {
        wallets: Wallet[];
        categories: CategoryWithSubcategories[];
        subcategories: Subcategory[];
        date: string;
        onSave: () => void;
        onCancel: () => void;
        onDateChange: (date: string) => void;
    }

    let {
        wallets,
        categories,
        subcategories,
        date,
        onSave,
        onCancel,
        onDateChange,
    }: Props = $props();

    let newRow = $state({
        // date is now managed by parent
        time: "",
        description: "",
        wallet_id: wallets[0]?.id || 0,
        direction: "outflow" as Direction,
        amount: "",
        classification: "expense" as Classification,
        category_id: null as number | null,
        subcategory_id: null as number | null,
    });

    let invalidFields = $state<Set<string>>(new Set());

    async function saveNewRow() {
        const errors = new Set<string>();

        // Description is optional now
        // if (!newRow.description.trim()) {
        //     alert("Description is required");
        //     return;
        // }

        if (!newRow.amount || parseFloat(newRow.amount) <= 0) {
            errors.add("amount");
        }

        if (errors.size > 0) {
            invalidFields = errors;
            return;
        }

        // Clear errors if valid
        invalidFields = new Set();

        try {
            await api.transactions.create({
                date: date,
                time: newRow.time || undefined,
                wallet_id: newRow.wallet_id,
                direction: newRow.direction,
                amount: parseFloat(newRow.amount),
                classification: newRow.classification,
                description: newRow.description
                    ? newRow.description.trim()
                    : "",
                category_id: newRow.category_id || undefined,
                subcategory_id: newRow.subcategory_id || undefined,
            });

            // Reset form
            newRow = {
                // date reset handled by parent if needed, but usually we keep same date or reset to today
                time: "",
                description: "",
                wallet_id: wallets[0]?.id || 0,
                direction: "outflow",
                amount: "",
                classification: "expense",
                category_id: null,
                subcategory_id: null,
            };

            onSave();
        } catch (err) {
            console.error("Failed to create transaction:", err);
        }
    }

    function handleKeyDown(event: KeyboardEvent) {
        if (event.key === "Enter") {
            event.preventDefault();
            event.stopPropagation();
            saveNewRow();
        } else if (event.key === "Escape") {
            event.preventDefault();
            event.stopPropagation();
            onCancel();
        }
    }
</script>

<tr class="new-row">
    <!-- Date Cell Removed -->

    <td class="category-cell">
        <select
            value={newRow.subcategory_id ||
                (newRow.category_id ? `cat_${newRow.category_id}` : null)}
            onchange={(e) => {
                const value = (e.target as HTMLSelectElement).value;
                if (!value || value === "null") {
                    newRow.category_id = null;
                    newRow.subcategory_id = null;
                } else if (value.startsWith("cat_")) {
                    newRow.category_id = parseInt(value.replace("cat_", ""));
                    newRow.subcategory_id = null;
                } else {
                    const subcatId = parseInt(value);
                    const subcat = subcategories.find((s) => s.id === subcatId);
                    newRow.subcategory_id = subcatId;
                    newRow.category_id = subcat?.category_id || null;
                }
            }}
            onkeydown={handleKeyDown}
        >
            <option value="null">None</option>
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
    </td>

    <td class="description-cell">
        <input
            type="text"
            bind:value={newRow.description}
            placeholder="Description..."
            onkeydown={handleKeyDown}
            autofocus
        />
    </td>

    <td class="amount-cell">
        <input
            type="number"
            class:error={invalidFields.has("amount")}
            bind:value={newRow.amount}
            placeholder="0.00"
            step="0.01"
            min="0"
            onkeydown={handleKeyDown}
        />
    </td>

    <td class="wallet-cell">
        <select bind:value={newRow.wallet_id} onkeydown={handleKeyDown}>
            {#each wallets as wallet}
                <option value={wallet.id}>{wallet.name}</option>
            {/each}
        </select>
    </td>

    <td class="type-cell">
        <div class="new-row-type-container">
            <select
                class="type-select"
                value={newRow.classification}
                onchange={(e) => {
                    const val = (e.target as HTMLSelectElement).value;
                    if (val === "income") {
                        newRow.classification = "income";
                        newRow.direction = "inflow";
                    } else {
                        newRow.classification = "expense";
                        newRow.direction = "outflow";
                    }
                }}
                onkeydown={handleKeyDown}
            >
                <option value="expense">{$t.transactionTypes.expense}</option>
                <option value="income">{$t.transactionTypes.income}</option>
            </select>
            <div class="new-row-actions">
                <button
                    class="save-btn"
                    onclick={saveNewRow}
                    title="Save (Enter)"
                >
                    ✓
                </button>
                <button
                    class="cancel-btn"
                    onclick={onCancel}
                    title="Cancel (Esc)"
                >
                    ✕
                </button>
            </div>
        </div>
    </td>
</tr>

<style>
    .new-row {
        background-color: rgba(0, 122, 255, 0.05);
        border: 2px solid var(--accent);
    }

    td {
        padding: var(--space-3) var(--space-4);
        border-bottom: 1px solid var(--border-light);
        font-size: var(--font-size-base);
    }

    .date-cell input,
    .description-cell input,
    .amount-cell input,
    .category-cell select,
    .wallet-cell select {
        width: 100%;
        padding: var(--space-1) var(--space-2);
        border: 1px solid var(--border); /* Added border for inputs */
        border-radius: var(--radius-sm);
    }

    input.error {
        border-color: var(--error);
        background-color: rgba(255, 59, 48, 0.05); /* Light red background */
    }

    .date-cell input {
        width: 120px;
    }
    .amount-cell input {
        width: 120px;
        text-align: right;
    }

    .new-row-type-container {
        display: flex;
        align-items: center;
        gap: var(--space-2);
    }

    .type-select {
        padding: var(--space-1);
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
        font-size: var(--font-size-xs);
        background-color: white;
        max-width: 80px;
    }

    .new-row-actions {
        display: flex;
        gap: var(--space-2);
        justify-content: center;
    }

    .save-btn,
    .cancel-btn {
        width: 28px;
        height: 28px;
        padding: 0;
        border-radius: var(--radius-sm);
        font-size: var(--font-size-base);
        line-height: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        border: none;
        cursor: pointer;
    }

    .save-btn {
        background-color: var(--success);
        color: white;
    }

    .save-btn:hover {
        background-color: #28a745;
    }

    .cancel-btn {
        background-color: var(--error);
        color: white;
    }

    .cancel-btn:hover {
        background-color: #e62e25;
    }
</style>
