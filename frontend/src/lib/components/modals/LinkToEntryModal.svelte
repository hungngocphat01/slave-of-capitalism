<script lang="ts">
    import { onMount } from "svelte";
    import { api } from "$lib/api/client";
    import type { PopulatedTransaction, LinkedEntry } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { t } from "$lib/i18n";

    interface Props {
        transaction: PopulatedTransaction | PopulatedTransaction[];
        onClose: () => void;
        onSave: () => void;
    }

    let { transaction, onClose, onSave }: Props = $props();

    let pendingEntries = $state<LinkedEntry[]>([]);
    let selectedEntryId = $state<number | null>(null);
    let loading = $state(true);
    let saving = $state(false);
    let error = $state<string | null>(null);

    async function loadPendingEntries() {
        loading = true;
        error = null;

        try {
            const entries = await api.linkedEntries.getPending();

            // Determine direction based on first transaction
            // (Assumes all selected transactions have same direction, enforced by caller)
            const firstTxn = Array.isArray(transaction)
                ? transaction[0]
                : transaction;

            if (firstTxn.direction === "inflow") {
                // If we are receiving money, we can link to:
                // 1. Split Payments (we paid for others, they are paying us back)
                // 2. Loans (we lent money, they are paying us back)
                pendingEntries = entries.filter(
                    (e) =>
                        e.link_type === "split_payment" ||
                        e.link_type === "loan",
                );
            } else {
                // If we are paying money, we can link to:
                // 1. Debts (we borrowed money, we are paying it back)
                pendingEntries = entries.filter((e) => e.link_type === "debt");
            }
        } catch (err) {
            console.error("Error loading pending entries:", err);
        } finally {
            loading = false;
        }
    }

    async function handleSubmit() {
        error = null;

        if (!selectedEntryId) {
            error = "Please select an entry to link to";
            return;
        }

        saving = true;

        try {
            if (Array.isArray(transaction)) {
                await api.transactions.linkTransactions(
                    transaction.map((t) => t.id),
                    selectedEntryId,
                );
            } else {
                await api.transactions.linkToEntry(transaction.id, {
                    linked_entry_id: selectedEntryId,
                });
            }

            onSave();
        } catch (err) {
            error =
                err instanceof Error ? err.message : "Failed to link to entry";
            console.error("Error linking to entry:", err);
        } finally {
            saving = false;
        }
    }

    onMount(() => {
        loadPendingEntries();
    });
</script>

<Modal title={$t.linkModal.title} {onClose}>
    <div class="link-form">
        {#if error}
            <div class="error-banner">
                ❌ {error}
            </div>
        {/if}

        {#if loading}
            <div class="loading-state">
                <div class="spinner"></div>
                <p>Loading pending entries...</p>
            </div>
        {:else if pendingEntries.length === 0}
            <div class="empty-state">
                <p>{$t.linkModal.noEntries}</p>
                <p class="help-text">
                    {$t.linkModal.helpText}
                </p>
            </div>
        {:else}
            <form
                id="link-form"
                onsubmit={(e) => {
                    e.preventDefault();
                    handleSubmit();
                }}
            >
                <div class="info-box">
                    <p class="info-label">
                        {#if Array.isArray(transaction)}
                            {$t.linkModal.totalAmount}
                        {:else}
                            {$t.linkModal.transactionAmount}
                        {/if}
                    </p>
                    <p class="info-value">
                        ¥{(Array.isArray(transaction)
                            ? transaction.reduce(
                                  (sum, t) => sum + Number(t.amount),
                                  0,
                              )
                            : Number(transaction.amount)
                        ).toLocaleString()}
                    </p>
                    <p class="help-text">
                        {$t.linkModal.willBeLinked}
                    </p>
                </div>

                <div class="form-group">
                    <p class="info-label">{$t.linkModal.selectEntry}</p>
                    <div class="entries-list">
                        {#each pendingEntries as entry}
                            <label class="entry-item">
                                <input
                                    type="radio"
                                    name="entry"
                                    value={entry.id}
                                    bind:group={selectedEntryId}
                                />
                                <div class="entry-details">
                                    <div class="entry-header">
                                        <span class="entry-name">
                                            {entry.primary_transaction_description ||
                                                entry.counterparty_name}
                                        </span>
                                        <div class="entry-amounts">
                                            <span class="entry-total"
                                                >Total: ¥{entry.total_amount.toLocaleString()}</span
                                            >
                                            <span class="entry-pending"
                                                >Left: ¥{entry.pending_amount.toLocaleString()}</span
                                            >
                                        </div>
                                    </div>
                                    <div class="entry-meta">
                                        <span class="entry-type">
                                            {entry.link_type === "split_payment"
                                                ? "💰" + $t.pending.splitPayment
                                                : "💸" + $t.pending.loan}
                                        </span>
                                        <span class="entry-status"
                                            >{entry.status == "partial"
                                                ? $t.pending.statusPartial
                                                : entry.status == "settled"
                                                  ? $t.pending.statusSettled
                                                  : $t.pending
                                                        .statusPending}</span
                                        >
                                    </div>
                                </div>
                            </label>
                        {/each}
                    </div>
                </div>
            </form>
        {/if}
    </div>

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
            form="link-form"
            disabled={saving}
        >
            {saving ? "Linking..." : "Link"}
        </button>
    {/snippet}
</Modal>

<style>
    .empty-state p {
        margin: 0;
        text-align: center;
    }

    .entries-list {
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
        max-height: 300px;
        overflow-y: auto;
    }

    .entry-item {
        display: flex;
        gap: var(--space-3);
        padding: var(--space-3);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        cursor: pointer;
        transition: all var(--transition-base);
        align-items: center;
    }

    .entry-item:hover {
        background-color: var(--surface);
        border-color: var(--accent);
    }

    .entry-item:has(input:checked) {
        background-color: rgba(0, 122, 255, 0.08);
        border-color: var(--accent);
    }

    .entry-details {
        flex: 1;
    }

    .entry-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: var(--space-1);
    }

    .entry-name {
        font-weight: var(--font-weight-semibold);
        font-size: var(--font-size-sm);
        color: var(--text-primary);
    }

    .entry-amounts {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
    }

    .entry-total {
        font-size: var(--font-size-sm);
        font-weight: var(--font-weight-bold);
        color: var(--text-primary);
    }

    .entry-pending {
        font-size: var(--font-size-xs);
        color: var(--text-secondary);
    }

    .entry-meta {
        display: flex;
        gap: var(--space-3);
        font-size: var(--font-size-xs);
        color: var(--text-secondary);
    }
</style>
