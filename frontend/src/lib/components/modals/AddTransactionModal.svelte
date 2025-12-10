<script lang="ts">
    import { api } from "$lib/api/client";
    import type {
        Wallet,
        Category,
        Direction,
        Classification,
    } from "$lib/api/types";
    import Modal from "./Modal.svelte";

    interface Props {
        wallets: Wallet[];
        categories: Category[];
        onClose: () => void;
        onSave: () => void;
    }

    let { wallets, categories, onClose, onSave }: Props = $props();

    let date = $state(new Date().toISOString().split("T")[0]);
    let time = $state("");
    let wallet_id = $state(wallets[0]?.id || 0);
    let direction = $state<Direction>("outflow");
    let amount = $state("");
    let classification = $state<Classification>("expense");
    let description = $state("");
    let category_id = $state<number | null>(null);
    let saving = $state(false);
    let error = $state<string | null>(null);

    const classificationOptions: { value: Classification; label: string }[] = [
        { value: "expense", label: "Expense" },
        { value: "income", label: "Income" },
        { value: "lend", label: "Lend" },
        { value: "borrow", label: "Borrow" },
        { value: "debt_collection", label: "Debt Collection" },
        { value: "loan_repayment", label: "Loan Repayment" },
        { value: "split_payment", label: "Split Payment" },
        { value: "transfer", label: "Transfer" },
    ];

    async function handleSubmit() {
        error = null;

        if (!description.trim()) {
            error = "Description is required";
            return;
        }

        if (!amount || parseFloat(amount) <= 0) {
            error = "Amount must be greater than 0";
            return;
        }

        saving = true;

        try {
            await api.transactions.create({
                date,
                time: time || undefined,
                wallet_id,
                direction,
                amount: parseFloat(amount),
                classification,
                description: description.trim(),
                category_id: category_id || undefined,
            });

            onSave();
        } catch (err) {
            error =
                err instanceof Error
                    ? err.message
                    : "Failed to create transaction";
            console.error("Error creating transaction:", err);
        } finally {
            saving = false;
        }
    }
</script>

<Modal title="Add Transaction" {onClose}>
    <form
        class="transaction-form"
        onsubmit={(e) => {
            e.preventDefault();
            handleSubmit();
        }}
    >
        {#if error}
            <div class="error-banner">
                ❌ {error}
            </div>
        {/if}

        <div class="form-row">
            <div class="form-group">
                <label for="date">Date</label>
                <input type="date" id="date" bind:value={date} required />
            </div>

            <div class="form-group">
                <label for="time">Time (optional)</label>
                <input type="time" id="time" bind:value={time} />
            </div>
        </div>

        <div class="form-group">
            <label for="description">Description</label>
            <input
                type="text"
                id="description"
                bind:value={description}
                placeholder="e.g., Dinner at restaurant"
                required
                autofocus
            />
        </div>

        <div class="form-row">
            <div class="form-group">
                <label for="direction">Direction</label>
                <select id="direction" bind:value={direction}>
                    <option value="outflow">Outflow (Expense)</option>
                    <option value="inflow">Inflow (Income)</option>
                </select>
            </div>

            <div class="form-group">
                <label for="amount">Amount</label>
                <input
                    type="number"
                    id="amount"
                    bind:value={amount}
                    placeholder="0.00"
                    step="0.01"
                    min="0"
                    required
                />
            </div>
        </div>

        <div class="form-group">
            <label for="wallet">Wallet</label>
            <select id="wallet" bind:value={wallet_id}>
                {#each wallets as wallet}
                    <option value={wallet.id}>{wallet.name}</option>
                {/each}
            </select>
        </div>

        <div class="form-group">
            <label for="classification">Classification</label>
            <select id="classification" bind:value={classification}>
                {#each classificationOptions as option}
                    <option value={option.value}>{option.label}</option>
                {/each}
            </select>
        </div>

        <div class="form-group">
            <label for="category">Category (optional)</label>
            <select id="category" bind:value={category_id}>
                <option value={null}>None</option>
                {#each categories as category}
                    <option value={category.id}>
                        {category.emoji}
                        {category.name}
                    </option>
                {/each}
            </select>
        </div>

        <div class="form-actions">
            <button
                type="button"
                class="secondary"
                onclick={onClose}
                disabled={saving}
            >
                Cancel
            </button>
            <button type="submit" disabled={saving}>
                {saving ? "Saving..." : "Add Transaction"}
            </button>
        </div>
    </form>
</Modal>

<style>
    .transaction-form {
        display: flex;
        flex-direction: column;
        gap: var(--space-4);
    }

    .error-banner {
        padding: var(--space-3);
        background-color: rgba(255, 59, 48, 0.1);
        border: 1px solid var(--error);
        border-radius: var(--radius-md);
        color: var(--error);
        font-size: var(--font-size-sm);
    }

    .form-row {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--space-4);
    }

    .form-group {
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
    }

    label {
        font-size: var(--font-size-sm);
        font-weight: var(--font-weight-semibold);
        color: var(--text-secondary);
    }

    input,
    select {
        width: 100%;
    }

    .form-actions {
        display: flex;
        justify-content: flex-end;
        gap: var(--space-3);
        margin-top: var(--space-4);
    }
</style>
