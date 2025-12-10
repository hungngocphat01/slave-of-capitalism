<script lang="ts">
    import type {
        PopulatedTransaction,
        Wallet,
        CategoryWithSubcategories,
        Subcategory,
    } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";

    let {
        transaction,
        wallets = [],
        categories = [],
        subcategories = [],
        onClose,
        onUpdate,
        onResolve,
    }: {
        transaction: PopulatedTransaction;
        wallets?: Wallet[];
        categories?: CategoryWithSubcategories[];
        subcategories?: Subcategory[];
        onClose: () => void;
        onUpdate?: () => void;
        onResolve?: () => void;
    } = $props();

    let isEditing = $state(true);
    let saving = $state(false);
    let error = $state<string | null>(null);

    // Edit state
    let editForm = $state({
        date: "",
        time: "",
        amount: "",
        description: "",
        category_id: null as number | null,
        subcategory_id: null as number | null,
        wallet_id: 0,
        // Split specific
        counterparty_name: "",
        user_amount: "",
        notes: "",
    });

    // Initialize form when transaction changes
    $effect(() => {
        initEditForm();
    });

    function initEditForm() {
        if (!transaction) return;
        editForm = {
            date: transaction.date,
            time: transaction.time || "",
            amount: transaction.amount.toString(),
            description: transaction.description,
            category_id: transaction.category_id || null,
            subcategory_id: transaction.subcategory_id || null,
            wallet_id: transaction.wallet_id,
            counterparty_name:
                transaction.linked_entry?.counterparty_name || "",
            user_amount:
                transaction.linked_entry?.user_amount?.toString() || "",
            notes: transaction.linked_entry?.notes || "",
        };
    }

    function formatAmount(amount: number) {
        return new Intl.NumberFormat("en-US", {
            style: "decimal",
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
        }).format(amount);
    }

    const isSplit = $derived(
        transaction.classification === "split_payment" &&
            !!transaction.linked_entry,
    );

    const isLoanOrDebt = $derived(
        (transaction.classification === "lend" ||
            transaction.classification === "borrow") &&
            !!transaction.linked_entry,
    );

    const hasLinkedEntry = $derived(isSplit || isLoanOrDebt);

    // Calculate collected amount: Total - User Share - Pending
    // Note: collectedAmount is fixed based on database state for now?
    // Actually, if we edit Total or User Share, we might imply Collected or Pending changes.
    // Usually: Total = UserShare + Collected + Pending.
    // Collected is usually actual payments received.
    // If we only edit Title/Date/Amount, we shouldn't change Collected.
    // So Pending = Total - UserShare - Collected.

    // We need the original collected amount (that isn't in editForm).
    // Original Paid = Original UserShare + Original Collected + Original Pending.
    // So Original Collected = Original Total - Original UserShare - Original Pending.
    const originalCollectedAmount = $derived(
        transaction.linked_entry
            ? transaction.amount -
                  (transaction.linked_entry.user_amount || 0) -
                  transaction.linked_entry.pending_amount
            : 0,
    );

    // Calculated pending amount while editing
    const editPendingAmount = $derived.by(() => {
        if (!transaction.linked_entry) return 0;
        const total = parseFloat(editForm.amount) || 0;
        // For Loan/Debt, user_amount is 0/null effectively, so Pending = Total - Collected
        const userAmt = isSplit ? parseFloat(editForm.user_amount) || 0 : 0;

        // Return max(0, ...)
        const pending = total - userAmt - originalCollectedAmount;
        return pending > 0 ? pending : 0;
    });

    async function handleSave() {
        saving = true;
        error = null;

        try {
            // 1. Update Transaction
            await api.transactions.update(transaction.id, {
                date: editForm.date,
                time: editForm.time || undefined,
                amount: parseFloat(editForm.amount),
                description: editForm.description,
                category_id: editForm.category_id || undefined,
                subcategory_id: editForm.subcategory_id || undefined,
                wallet_id: editForm.wallet_id,
            });

            // 2. Update Linked Entry (if exists)
            if (hasLinkedEntry && transaction.linked_entry) {
                await api.linkedEntries.update(transaction.linked_entry.id, {
                    counterparty_name: editForm.counterparty_name,
                    user_amount: isSplit
                        ? parseFloat(editForm.user_amount)
                        : undefined,
                    notes: editForm.notes,
                });
            }

            if (onUpdate) onUpdate();
            onClose(); // Close modal on success
        } catch (err) {
            console.error("Failed to save changes:", err);
            error =
                err instanceof Error
                    ? err.message
                    : $t.transactions.failedToSave;
        } finally {
            saving = false;
        }
    }

    async function handleToggleIgnore() {
        try {
            if (transaction.is_ignored) {
                await api.transactions.unignore(transaction.id);
            } else {
                await api.transactions.ignore(transaction.id);
            }
            if (onUpdate) onUpdate();
            onClose();
        } catch (err) {
            console.error(err);
        }
    }
</script>

<Modal title={$t.transactions.detailsTitle} {onClose}>
    <div class="badges">
        {#if transaction.is_ignored}
            <span class="badge ignored"
                >{$t.transactions?.ignored || "⛔ Ignored"}</span
            >
        {/if}
        {#if transaction.is_calibration}
            <span class="badge calibration"
                >{$t.transactions?.calibration || "⚖️ Calibration"}</span
            >
        {/if}
    </div>

    {#if error}
        <div class="error-banner">
            {error}
        </div>
    {/if}

    <!-- EDIT FORM -->
    <div class="edit-form">
        <!-- Basic Fields -->
        <div class="form-row">
            <div class="form-group">
                <label for="date-input">{$t.common.date}</label>
                <input id="date-input" type="date" bind:value={editForm.date} />
            </div>
            <div class="form-group">
                <label for="time-input">{$t.common.time}</label>
                <input id="time-input" type="time" bind:value={editForm.time} />
            </div>
        </div>

        <div class="form-group">
            <label for="amount-input">{$t.common.amount}</label>
            <input
                id="amount-input"
                type="number"
                step="0.01"
                bind:value={editForm.amount}
            />
        </div>

        <div class="form-group">
            <label for="desc-input">{$t.common.description}</label>
            <input
                id="desc-input"
                type="text"
                bind:value={editForm.description}
            />
        </div>

        <div class="form-group">
            <label for="category-select">{$t.common.category}</label>
            <select
                id="category-select"
                value={editForm.subcategory_id ||
                    (editForm.category_id ? `cat_${editForm.category_id}` : "")}
                onchange={(e) => {
                    const value = (e.target as HTMLSelectElement).value;
                    if (!value) {
                        editForm.category_id = null;
                        editForm.subcategory_id = null;
                    } else if (value.startsWith("cat_")) {
                        editForm.category_id = parseInt(
                            value.replace("cat_", ""),
                        );
                        editForm.subcategory_id = null;
                    } else {
                        const subId = parseInt(value);
                        const sub = subcategories.find((s) => s.id === subId);
                        editForm.subcategory_id = subId;
                        editForm.category_id = sub?.category_id || null;
                    }
                }}
            >
                <option value="">{$t.transactions.uncategorized}</option>
                {#each categories as category}
                    {#if category.subcategories && category.subcategories.length > 0}
                        <optgroup label="{category.emoji} {category.name}">
                            {#each category.subcategories as sub}
                                <option value={sub.id}>{sub.name}</option>
                            {/each}
                        </optgroup>
                    {:else}
                        <option value="cat_{category.id}"
                            >{category.emoji} {category.name}</option
                        >
                    {/if}
                {/each}
            </select>
        </div>

        <div class="form-group">
            <label for="wallet-select">{$t.common.wallet}</label>
            <select id="wallet-select" bind:value={editForm.wallet_id}>
                {#each wallets as wallet}
                    <option value={wallet.id}>{wallet.name}</option>
                {/each}
            </select>
        </div>

        <!-- Linked Entry Details -->
        {#if hasLinkedEntry && transaction.linked_entry}
            <div class="separator"></div>
            <h4 class="section-title">
                {#if isSplit}{$t.transactions.splitDetails}{/if}
                {#if isLoanOrDebt}{$t.transactions.loanDebtDetails}{/if}
            </h4>

            {#if isSplit}
                <div class="form-row">
                    <!-- Note: Amount is already edited above, but we can show it here too or just focus on the split parts -->
                    <div class="form-group">
                        <label for="my-part-input"
                            >{$t.transactions.myExpense}</label
                        >
                        <input
                            id="my-part-input"
                            type="number"
                            step="0.01"
                            bind:value={editForm.user_amount}
                        />
                    </div>

                    <div class="form-group">
                        <label for="original-collected"
                            >{$t.transactions.originalCollected}</label
                        >
                        <input
                            id="original-collected"
                            type="text"
                            value="¥{formatAmount(originalCollectedAmount)}"
                            disabled
                            class="text-success"
                        />
                    </div>
                </div>
            {/if}

            <div class="form-row">
                <div class="form-group">
                    <label for="counterparty-input"
                        >{$t.transactions.counterpartyName}</label
                    >
                    <input
                        id="counterparty-input"
                        type="text"
                        bind:value={editForm.counterparty_name}
                    />
                </div>
                <div class="form-group">
                    <label for="still-owed">{$t.transactions.stillOwed}</label>
                    <input
                        id="still-owed"
                        type="text"
                        value="¥{formatAmount(editPendingAmount)}"
                        disabled
                        class="text-warning"
                    />
                </div>
            </div>

            <div class="form-group">
                <label for="notes-input">{$t.common.notes}</label>
                <textarea id="notes-input" bind:value={editForm.notes} rows="2"
                ></textarea>
            </div>
        {/if}

        <div class="form-actions" style="justify-content: space-between;">
            <div class="left-actions">
                {#if transaction.is_calibration && onResolve}
                    <button class="btn warning" onclick={onResolve}>
                        Resolve Calibration
                    </button>
                {/if}
            </div>
        </div>
    </div>

    {#snippet footer()}
        <div class="form-actions spread" style="width: 100%; margin: 0;">
            <button
                class="btn mac-btn {transaction.is_ignored
                    ? 'secondary'
                    : 'warning-outline'}"
                onclick={handleToggleIgnore}
            >
                {transaction.is_ignored
                    ? "Unignore Transaction"
                    : "Ignore Transaction"}
            </button>
            <button
                class="btn mac-btn primary"
                onclick={handleSave}
                disabled={saving}
            >
                {saving ? "Saving..." : "Save Changes"}
            </button>
        </div>
    {/snippet}
</Modal>

<style>
    /* Form Styles */
    /* Form Styles */
    .badges {
        display: flex;
        gap: var(--space-2);
        margin-bottom: var(--space-2);
    }

    .section-title {
        margin: 0;
        font-size: var(--font-size-base);
        font-weight: 600;
        color: var(--text-primary);
    }

    .separator {
        border-top: 1px solid var(--border);
        margin: var(--space-2) 0;
    }

    .text-warning {
        color: var(--color-warning);
    }

    .text-success {
        color: var(--success);
    }
</style>
