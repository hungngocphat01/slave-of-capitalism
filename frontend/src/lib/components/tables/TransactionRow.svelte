<script lang="ts">
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type {
        PopulatedTransaction,
        Wallet,
        CategoryWithSubcategories,
        Subcategory,
    } from "$lib/api/types";
    import { Scale } from "svelte-heros-v2";

    interface Props {
        transaction: PopulatedTransaction;
        isSelected: boolean;
        editingField: string | null;
        wallets: Wallet[];
        categories: CategoryWithSubcategories[];
        subcategories: Subcategory[];
        onSelect: () => void;
        onContextMenu: (e: MouseEvent) => void;
        onEditStart: (field: string) => void;
        onEditEnd: () => void;
        onUpdate: () => void;
        isSelectionMode?: boolean;
    }

    let {
        transaction,
        isSelected,
        editingField,
        wallets,
        categories,
        subcategories,
        onSelect,
        onContextMenu,
        onEditStart,
        onEditEnd,
        onUpdate,
        isSelectionMode = false,
    }: Props = $props();

    let editValue = $state("");

    // Initialize editValue when editingField changes
    $effect(() => {
        if (editingField) {
            switch (editingField) {
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
    });

    function formatAmount(amount: number) {
        return (
            "¥" +
            new Intl.NumberFormat("en-US", {
                style: "decimal",
                minimumFractionDigits: 0,
                maximumFractionDigits: 0,
            }).format(amount)
        );
    }

    function formatDate(date: string): string {
        const d = new Date(date);
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const day = String(d.getDate()).padStart(2, "0");
        const weekday = days[d.getDay()];
        return `${day} (${weekday})`;
    }

    function getTransactionColor(t: PopulatedTransaction): string {
        if (t.classification === "transfer") return "transfer";
        if (t.classification === "split_payment") return "split";
        if (
            t.classification === "lend" ||
            t.classification === "loan_repayment" ||
            t.classification === "installmt_chrge"
        )
            return "loan";
        if (t.classification === "borrow") return "debt";
        // Debt collection is money coming back, so it shouldn't be red (debt color).
        // specific check or just fall through to inflow/outflow
        if (t.classification === "debt_collection") return "inflow";
        if (t.direction === "reserved") return "outflow"; // Placeholder style handles the gray color
        return t.direction === "inflow" ? "inflow" : "outflow";
    }

    async function saveEdit() {
        if (!editingField) return;

        try {
            const updates: any = {};

            switch (editingField) {
                case "date":
                    updates.date = editValue;
                    break;
                case "description":
                    updates.description = editValue;
                    break;
                case "amount":
                    updates.amount = parseFloat(editValue);
                    break;
                case "category":
                    const categoryValue = String(editValue);
                    if (
                        !categoryValue ||
                        categoryValue === "null" ||
                        categoryValue === ""
                    ) {
                        updates.category_id = null;
                        updates.subcategory_id = null;
                    } else if (categoryValue.startsWith("cat_")) {
                        updates.category_id = parseInt(
                            categoryValue.replace("cat_", ""),
                        );
                        updates.subcategory_id = null;
                    } else {
                        const subcatId = parseInt(categoryValue);
                        const subcat = subcategories.find(
                            (s) => s.id === subcatId,
                        );
                        updates.subcategory_id = subcatId;
                        updates.category_id = subcat?.category_id || null;
                    }
                    break;
                case "wallet":
                    updates.wallet_id = parseInt(editValue);
                    break;
            }

            await api.transactions.update(transaction.id, updates);
            onEditEnd();
            onUpdate();
        } catch (err) {
            console.error("Failed to update transaction:", err);
            // Alert removed to improve UX. The previous value will remain until refresh or retry.
        }
    }

    function handleKeyDown(event: KeyboardEvent) {
        if (event.key === "Enter") {
            saveEdit();
        } else if (event.key === "Escape") {
            onEditEnd();
        }
    }
</script>

<tr
    class="transaction-row"
    class:selected={isSelected}
    class:ignored={transaction.is_ignored}
    class:placeholder={transaction.classification === "installment"}
    onclick={onSelect}
    oncontextmenu={onContextMenu}
    role="button"
    tabindex="0"
>
    <!-- Category Cell -->
    <td class="category-cell" ondblclick={() => onEditStart("category")}>
        <div class="category-wrapper">
            {#if isSelectionMode}
                <div class="selection-checkbox">
                    <input
                        type="checkbox"
                        checked={isSelected}
                        onchange={onSelect}
                        onclick={(e) => e.stopPropagation()}
                    />
                </div>
            {/if}
            {#if editingField === "category"}
                <select
                    bind:value={editValue}
                    onblur={saveEdit}
                    onkeydown={handleKeyDown}
                    autofocus
                >
                    <option value="null">None</option>
                    {#each categories as category}
                        {#if category.subcategories && category.subcategories.length > 0}
                            <optgroup label="{category.emoji} {category.name}">
                                {#each category.subcategories as subcategory}
                                    <option value={String(subcategory.id)}>
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
            {:else}
                {@const subcat =
                    transaction.subcategory ||
                    (transaction.subcategory_id
                        ? subcategories.find(
                              (s) => s.id === transaction.subcategory_id,
                          )
                        : null)}
                {@const cat =
                    transaction.category ||
                    (transaction.category_id
                        ? categories.find(
                              (c) => c.id === transaction.category_id,
                          )
                        : null)}

                {#if subcat}
                    {cat?.emoji} {subcat.name}
                {:else if cat}
                    {cat.emoji} {cat.name}
                {:else}
                    <span class="text-tertiary">—</span>
                {/if}
            {/if}
        </div>
    </td>

    <!-- Description Cell -->
    <td class="description-cell" ondblclick={() => onEditStart("description")}>
        {#if editingField === "description"}
            <input
                type="text"
                bind:value={editValue}
                onblur={saveEdit}
                onkeydown={handleKeyDown}
                autofocus
            />
        {:else}
            {transaction.description}
        {/if}
    </td>

    <!-- Amount Cell -->
    <td
        class="amount-cell {getTransactionColor(transaction)}"
        ondblclick={() => onEditStart("amount")}
    >
        {#if editingField === "amount"}
            <input
                type="number"
                bind:value={editValue}
                onblur={saveEdit}
                onkeydown={handleKeyDown}
                autofocus
            />
        {:else if (transaction.classification === "split_payment" || transaction.classification === "installment") && transaction.linked_entry}
            <div class="split-amount-container">
                <span>{formatAmount(transaction.amount)}</span>
                <span
                    class="split-subtext"
                    title="Status: {transaction.linked_entry.status}"
                    >({transaction.linked_entry.status === "settled"
                        ? $t.pending.statusSettled
                        : transaction.linked_entry.status === "partial"
                          ? $t.pending.statusPartial
                          : $t.pending.statusPending})</span
                >
            </div>
        {:else if transaction.classification === "installmt_chrge" && transaction.is_linked_to_entry}
            <div class="split-amount-container">
                <span
                    >{transaction.direction === "outflow"
                        ? ""
                        : "+"}{formatAmount(transaction.amount)}</span
                >
                <span class="split-subtext">({$t.pending.linked})</span>
            </div>
        {:else}
            {transaction.direction === "inflow" ? "+" : ""}{formatAmount(
                transaction.amount,
            )}
        {/if}
    </td>

    <!-- Wallet Cell -->
    <td class="wallet-cell" ondblclick={() => onEditStart("wallet")}>
        {#if editingField === "wallet"}
            <select
                bind:value={editValue}
                onblur={saveEdit}
                onkeydown={handleKeyDown}
                autofocus
            >
                {#each wallets as wallet}
                    <option value={wallet.id}>{wallet.name}</option>
                {/each}
            </select>
        {:else}
            {wallets.find((w) => w.id === transaction.wallet_id)?.name ||
                "Unknown"}
        {/if}
    </td>

    <!-- Type Cell -->
    <td class="type-cell">
        <span class="type-badge {getTransactionColor(transaction)}">
            {$t.transactionTypes[
                transaction.classification as keyof typeof $t.transactionTypes
            ]}
        </span>
    </td>
</tr>

<style>
    /* Transaction row styles are now in src/styles/table.css */
    .category-wrapper {
        display: flex;
        align-items: center;
        gap: 8px;
    }
</style>
