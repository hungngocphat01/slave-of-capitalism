<script lang="ts">
    import { api } from "$lib/api/client";
    import type { PopulatedTransaction } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { t } from "$lib/i18n";

    interface Props {
        transaction: PopulatedTransaction;
        onClose: () => void;
        onSave: () => void;
    }

    let { transaction, onClose, onSave }: Props = $props();

    let counterparty_name = $state("");
    let user_amount = $state("");
    let notes = $state("");
    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleSubmit() {
        error = null;

        if (!counterparty_name.trim()) {
            error = $t.transactions.counterpartyNameRequired;
            return;
        }

        if (!user_amount || parseFloat(user_amount) <= 0) {
            error = $t.transactions.shareGreaterThanZero;
            return;
        }

        if (parseFloat(user_amount) > transaction.amount) {
            error = $t.transactions.shareExceedsTotal;
            return;
        }

        saving = true;

        try {
            await api.transactions.markAsSplit(transaction.id, {
                counterparty_name: counterparty_name.trim(),
                user_amount: parseFloat(user_amount),
                notes: notes.trim() || undefined,
            });

            onSave();
        } catch (err) {
            console.error("Error marking as split:", err);
        } finally {
            saving = false;
        }
    }

    const otherPersonAmount = $derived(
        user_amount ? transaction.amount - parseFloat(user_amount) : 0,
    );
</script>

<Modal title={$t.transactions.markAsSplitTitle} {onClose}>
    <form
        class="split-form"
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
            <p class="info-label">{$t.transactions.totalAmount}</p>
            <p class="info-value">¥{transaction.amount.toLocaleString()}</p>
        </div>

        <div class="form-group">
            <label for="counterparty">{$t.transactions.whoSplitWith}</label>
            <input
                type="text"
                id="counterparty"
                bind:value={counterparty_name}
                placeholder="e.g., Bob"
                required
            />
        </div>

        <div class="form-group">
            <label for="user-amount">{$t.transactions.yourShare}</label>
            <input
                type="number"
                id="user-amount"
                bind:value={user_amount}
                placeholder="0.00"
                step="0.01"
                min="0"
                max={transaction.amount}
                required
            />
            {#if user_amount}
                <p class="help-text">
                    {counterparty_name || "Other person"}
                    {$t.transactions.owes}: ¥{otherPersonAmount.toLocaleString()}
                </p>
            {/if}
        </div>

        <div class="form-group">
            <label for="notes">{$t.transactions.notesOptional}</label>
            <textarea
                id="notes"
                bind:value={notes}
                placeholder={$t.common.notes}
                rows="3"
            ></textarea>
        </div>
    </form>

    {#snippet footer()}
        <div class="form-actions right" style="width: 100%; margin: 0;">
            <button
                type="button"
                class="btn mac-btn secondary"
                onclick={onClose}
                disabled={saving}
            >
                {$t.common.cancel}
            </button>
            <button
                class="btn mac-btn primary"
                onclick={handleSubmit}
                disabled={saving}
            >
                {saving ? $t.common.loading : $t.transactions.markAsSplit}
            </button>
        </div>
    {/snippet}
</Modal>
