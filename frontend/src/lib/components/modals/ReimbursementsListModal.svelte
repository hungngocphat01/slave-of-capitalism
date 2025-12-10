<script lang="ts">
    import Modal from "./Modal.svelte";
    import type { PopulatedTransaction } from "$lib/api/types";
    import { t } from "$lib/i18n";

    interface Props {
        transaction: PopulatedTransaction;
        onClose: () => void;
    }

    let { transaction, onClose }: Props = $props();

    const linkedEntry = $derived(transaction.linked_entry);
    const linkedTransactions = $derived(linkedEntry?.linked_transactions || []);

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

    function formatDate(dateStr?: string) {
        if (!dateStr) return "-";
        return new Date(dateStr).toLocaleDateString();
    }
</script>

<Modal title={$t.reimbursementModal.title} {onClose}>
    <div class="header-info">
        <div class="info-row">
            <span class="label">{$t.reimbursementModal.totalAmount}</span>
            <span class="value"
                >{formatAmount(linkedEntry?.total_amount || 0)}</span
            >
        </div>
        <div class="info-row">
            <span class="label">{$t.reimbursementModal.remainingPending}</span>
            <span class="value text-warning"
                >{formatAmount(linkedEntry?.pending_amount || 0)}</span
            >
        </div>
    </div>

    <h4>{$t.reimbursementModal.linkedTransactions}</h4>

    {#if linkedTransactions.length === 0}
        <div class="empty-state">
            {$t.reimbursementModal.noReimbursements}
        </div>
    {:else}
        <div class="list">
            {#each linkedTransactions as link}
                <div class="list-item">
                    <div class="item-main">
                        <span class="date">{formatDate(link.date)}</span>
                        <span class="description"
                            >{link.description ||
                                $t.reimbursementModal.noDescription}</span
                        >
                    </div>
                    <div class="item-amount">
                        {formatAmount(link.amount)}
                    </div>
                </div>
            {/each}
        </div>
    {/if}

    {#snippet footer()}
        <button class="btn mac-btn secondary" onclick={onClose}
            >{$t.common.close}</button
        >
    {/snippet}
</Modal>

<style>
    .header-info {
        background: var(--surface);
        padding: var(--space-3);
        border-radius: var(--radius-md);
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
    }

    .info-row {
        display: flex;
        justify-content: space-between;
        font-size: var(--font-size-sm);
    }

    .label {
        color: var(--text-secondary);
    }

    .value {
        font-weight: 600;
        color: var(--text-primary);
    }

    h4 {
        margin: 0;
        font-size: var(--font-size-base);
        color: var(--text-primary);
        padding-top: var(--space-3);
        padding-bottom: var(--space-2);
    }

    .empty-state {
        color: var(--text-tertiary);
        text-align: center;
        padding: var(--space-4);
        font-style: italic;
    }

    .list {
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
        max-height: 300px;
        overflow-y: auto;
    }

    .list-item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: var(--space-2) var(--space-3);
        border: 1px solid var(--border-light);
        border-radius: var(--radius-sm);
    }

    .item-main {
        display: flex;
        flex-direction: column;
        gap: 2px;
    }

    .date {
        font-size: var(--font-size-xs);
        color: var(--text-tertiary);
    }

    .description {
        font-size: var(--font-size-sm);
        font-weight: 500;
    }

    .item-amount {
        font-weight: 600;
        color: var(--inflow);
    }
</style>
