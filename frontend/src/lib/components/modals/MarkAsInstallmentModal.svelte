<script lang="ts">
    import { api } from "$lib/api/client";
    import type { PopulatedTransaction } from "$lib/api/types";
    import { t } from "$lib/i18n";
    import Modal from "./Modal.svelte";

    interface Props {
        transaction: PopulatedTransaction;
        onClose: () => void;
        onSave: () => void;
    }

    let { transaction, onClose, onSave }: Props = $props();

    let notes = $state("");
    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleSubmit() {
        error = null;
        saving = true;

        try {
            // Auto-fill counterparty with wallet name (required by backend)
            await api.transactions.markAsInstallment(transaction.id, {
                counterparty_name: transaction.wallet_name || "Installment",
                notes: notes.trim() || undefined,
            });

            onSave();
        } catch (err) {
            error =
                err instanceof Error
                    ? err.message
                    : "Failed to mark as installment";
            console.error("Error marking as installment:", err);
        } finally {
            saving = false;
        }
    }
</script>

<Modal title={$t.transactions.markAsInstallment} {onClose}>
    <form
        class="installment-form"
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
            <p class="info-label">{$t.common.amount}</p>
            <p class="info-value">¥{transaction.amount.toLocaleString()}</p>
        </div>

        <div class="form-group">
            <label for="notes">{$t.transactions.notesOptional}</label>
            <textarea
                id="notes"
                bind:value={notes}
                placeholder="e.g., Laptop - 3 months, Phone - 6 months"
                rows="3"
                autofocus
            ></textarea>
        </div>

        <div class="form-actions">
            <button
                type="button"
                class="secondary"
                onclick={onClose}
                disabled={saving}
            >
                {$t.common.cancel}
            </button>
            <button type="submit" disabled={saving}>
                {saving ? $t.common.loading : $t.transactions.markAsInstallment}
            </button>
        </div>
    </form>
</Modal>

<style>
    .installment-form {
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
