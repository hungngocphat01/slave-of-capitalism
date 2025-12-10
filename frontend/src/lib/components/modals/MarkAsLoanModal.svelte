<script lang="ts">
    import { api } from "$lib/api/client";
    import type { PopulatedTransaction } from "$lib/api/types";
    import Modal from "./Modal.svelte";

    interface Props {
        transaction: PopulatedTransaction;
        isDebt?: boolean;
        onClose: () => void;
        onSave: () => void;
    }

    let { transaction, isDebt = false, onClose, onSave }: Props = $props();

    let counterparty_name = $state("");
    let notes = $state("");
    let saving = $state(false);
    let error = $state<string | null>(null);

    const title = isDebt ? "Mark as Debt" : "Mark as Loan";
    const actionLabel = isDebt ? "Mark as Debt" : "Mark as Loan";

    async function handleSubmit() {
        error = null;

        if (!counterparty_name.trim()) {
            error = "Counterparty name is required";
            return;
        }

        saving = true;

        try {
            if (isDebt) {
                await api.transactions.markAsDebt(transaction.id, {
                    counterparty_name: counterparty_name.trim(),
                    notes: notes.trim() || undefined,
                });
            } else {
                await api.transactions.markAsLoan(transaction.id, {
                    counterparty_name: counterparty_name.trim(),
                    notes: notes.trim() || undefined,
                });
            }

            onSave();
        } catch (err) {
            error =
                err instanceof Error
                    ? err.message
                    : `Failed to ${actionLabel.toLowerCase()}`;
            console.error(`Error ${actionLabel.toLowerCase()}:`, err);
        } finally {
            saving = false;
        }
    }
</script>

<Modal {title} {onClose}>
    <form
        class="loan-form"
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

        <div class="info-box">
            <p class="info-label">Amount</p>
            <p class="info-value">¥{transaction.amount.toLocaleString()}</p>
        </div>

        <div class="form-group">
            <label for="counterparty">
                {isDebt ? "Who did you borrow from?" : "Who did you lend to?"}
            </label>
            <input
                type="text"
                id="counterparty"
                bind:value={counterparty_name}
                placeholder="e.g., Alice"
                required
                autofocus
            />
        </div>

        <div class="form-group">
            <label for="notes">Notes (optional)</label>
            <textarea
                id="notes"
                bind:value={notes}
                placeholder="Add any additional details..."
                rows="3"
            ></textarea>
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
                {saving ? "Saving..." : actionLabel}
            </button>
        </div>
    </form>
</Modal>

<style>
    .loan-form {
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

    .info-box {
        padding: var(--space-4);
        background-color: var(--surface);
        border-radius: var(--radius-md);
        border: 1px solid var(--border);
    }

    .info-label {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        margin: 0 0 var(--space-1) 0;
    }

    .info-value {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-bold);
        color: var(--text-primary);
        margin: 0;
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
    textarea {
        width: 100%;
    }

    .form-actions {
        display: flex;
        justify-content: flex-end;
        gap: var(--space-3);
        margin-top: var(--space-4);
    }
</style>
