<script lang="ts">
    import { onMount } from "svelte";
    import { api } from "$lib/api/client";
    import type { LinkedEntry } from "$lib/api/types";
    import { t } from "$lib/i18n";

    let pendingEntries = $state<LinkedEntry[]>([]);
    let loading = $state(true);
    let error = $state<string | null>(null);

    async function loadPendingEntries() {
        loading = true;
        error = null;

        try {
            pendingEntries = await api.linkedEntries.getPending();
        } catch (err) {
            error =
                err instanceof Error
                    ? err.message
                    : "Failed to load pending entries";
            console.error("Error loading pending entries:", err);
        } finally {
            loading = false;
        }
    }

    function formatAmount(amount: number): string {
        return new Intl.NumberFormat("ja-JP", {
            style: "currency",
            currency: "JPY",
            minimumFractionDigits: 0,
        }).format(amount);
    }

    function formatDate(dateString: string): string {
        const date = new Date(dateString);
        return date.toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
        });
    }

    function getLinkTypeLabel(linkType: string): string {
        switch (linkType) {
            case "split_payment":
                return `💰 ${$t.pending.splitPayment}`;
            case "loan":
                return `💸 ${$t.pending.loan}`;
            case "debt":
                return `🏦 ${$t.pending.debt}`;
            case "installment":
                return `💳 ${$t.pending.installment}`;
            default:
                return linkType;
        }
    }

    function getStatusColor(status: string): string {
        switch (status) {
            case "pending":
                return "var(--warning)";
            case "partial":
                return "var(--accent)";
            case "settled":
                return "var(--success)";
            default:
                return "var(--text-secondary)";
        }
    }

    function getStatusLabel(status: string): string {
        switch (status) {
            case "pending":
                return $t.pending.statusPending;
            case "partial":
                return $t.pending.statusPartial;
            case "settled":
                return $t.pending.statusSettled;
            default:
                return status.toUpperCase();
        }
    }

    // Separate entries into "owed to me" and "I owe"
    let peopleOweMe = $derived(
        pendingEntries.filter(
            (entry) =>
                entry.link_type === "split_payment" ||
                entry.link_type === "loan",
        ),
    );

    let iOwe = $derived(
        pendingEntries.filter((entry) => entry.link_type === "debt"),
    );

    let installmentPlans = $derived(
        pendingEntries.filter((entry) => entry.link_type === "installment"),
    );

    let totalOwedToMe = $derived(
        peopleOweMe.reduce(
            (sum: number, entry) => sum + (Number(entry.pending_amount) || 0),
            0,
        ),
    );

    let totalIOwe = $derived(
        iOwe.reduce(
            (sum: number, entry) => sum + (Number(entry.pending_amount) || 0),
            0,
        ),
    );

    let totalInstallments = $derived(
        installmentPlans.reduce(
            (sum: number, entry) => sum + (Number(entry.pending_amount) || 0),
            0,
        ),
    );

    onMount(() => {
        loadPendingEntries();

        // Refresh when window gets focus (in case transaction was updated in another tab/modal)
        const onFocus = () => loadPendingEntries();
        window.addEventListener("focus", onFocus);

        return () => {
            window.removeEventListener("focus", onFocus);
        };
    });
</script>

<div class="pending-screen">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.pending.pageTitle}</h1>
            <button
                class="refresh-btn"
                onclick={loadPendingEntries}
                disabled={loading}
            >
                🔄 {$t.common.refresh}
            </button>
        </div>
    </header>

    <div class="screen-content">
        {#if loading}
            <div class="loading-state">
                <div class="spinner"></div>
                <p>{$t.pending.loading}</p>
            </div>
        {:else if error}
            <div class="error-state">
                <p class="error-message">❌ {error}</p>
                <button class="retry-btn" onclick={loadPendingEntries}>
                    {$t.common.retry}
                </button>
            </div>
        {:else}
            <!-- People Owe Me Section -->
            <section class="pending-section">
                <div class="section-header">
                    <h2 class="section-title">{$t.pending.peopleOweYou}</h2>
                    <div class="section-total" style="color: var(--success)">
                        {formatAmount(totalOwedToMe)}
                    </div>
                </div>

                {#if peopleOweMe.length === 0}
                    <div class="empty-state">
                        <p>{$t.pending.noPendingReimbursements}</p>
                    </div>
                {:else}
                    <div class="entries-list">
                        {#each peopleOweMe as entry}
                            <div class="entry-card">
                                <div class="entry-header">
                                    <div class="entry-info">
                                        <div class="counterparty-name">
                                            {entry.counterparty_name}
                                        </div>
                                        {#if entry.primary_transaction_description}
                                            <div class="entry-description">
                                                {entry.primary_transaction_description}
                                            </div>
                                        {/if}
                                    </div>
                                    <div
                                        class="entry-amount"
                                        style="color: var(--success)"
                                    >
                                        {formatAmount(entry.pending_amount)}
                                    </div>
                                </div>
                                <div class="entry-details">
                                    <span class="entry-type"
                                        >{getLinkTypeLabel(
                                            entry.link_type,
                                        )}</span
                                    >
                                    <span class="entry-date">
                                        {formatDate(entry.created_at)}
                                    </span>
                                    <span
                                        class="entry-status"
                                        style="color: {getStatusColor(
                                            entry.status,
                                        )}"
                                    >
                                        {getStatusLabel(entry.status)}
                                    </span>
                                </div>
                                {#if entry.notes}
                                    <div class="entry-notes">{entry.notes}</div>
                                {/if}
                                {#if entry.linked_transactions && entry.linked_transactions.length > 0}
                                    <div class="payments-received">
                                        <div class="payments-header">
                                            {$t.pending.paymentsReceived}:
                                        </div>
                                        {#each entry.linked_transactions as payment}
                                            <div class="payment-item">
                                                ✅ {payment.date
                                                    ? formatDate(payment.date)
                                                    : "N/A"} - {formatAmount(
                                                    payment.amount,
                                                )}
                                                {#if payment.description}
                                                    <span class="payment-desc"
                                                        >({payment.description})</span
                                                    >
                                                {/if}
                                            </div>
                                        {/each}
                                    </div>
                                {/if}
                            </div>
                        {/each}
                    </div>
                {/if}
            </section>

            <!-- I Owe Section -->
            <section class="pending-section">
                <div class="section-header">
                    <h2 class="section-title">{$t.pending.youOwe}</h2>
                    <div class="section-total" style="color: var(--error)">
                        {formatAmount(totalIOwe)}
                    </div>
                </div>

                {#if iOwe.length === 0}
                    <div class="empty-state">
                        <p>{$t.pending.noPendingDebts}</p>
                    </div>
                {:else}
                    <div class="entries-list">
                        {#each iOwe as entry}
                            <div class="entry-card">
                                <div class="entry-header">
                                    <div class="entry-info">
                                        <div class="counterparty-name">
                                            {entry.counterparty_name}
                                        </div>
                                        {#if entry.primary_transaction_description}
                                            <div class="entry-description">
                                                {entry.primary_transaction_description}
                                            </div>
                                        {/if}
                                    </div>
                                    <div
                                        class="entry-amount"
                                        style="color: var(--error)"
                                    >
                                        {formatAmount(entry.pending_amount)}
                                    </div>
                                </div>
                                <div class="entry-details">
                                    <span class="entry-type"
                                        >{getLinkTypeLabel(
                                            entry.link_type,
                                        )}</span
                                    >
                                    <span class="entry-date">
                                        {formatDate(entry.created_at)}
                                    </span>
                                    <span
                                        class="entry-status"
                                        style="color: {getStatusColor(
                                            entry.status,
                                        )}"
                                    >
                                        {getStatusLabel(entry.status)}
                                    </span>
                                </div>
                                {#if entry.notes}
                                    <div class="entry-notes">{entry.notes}</div>
                                {/if}
                                {#if entry.linked_transactions && entry.linked_transactions.length > 0}
                                    <div class="payments-received">
                                        <div class="payments-header">
                                            {$t.pending.repaymentsMade}:
                                        </div>
                                        {#each entry.linked_transactions as payment}
                                            <div class="payment-item">
                                                ✅ {payment.date
                                                    ? formatDate(payment.date)
                                                    : "N/A"} - {formatAmount(
                                                    payment.amount,
                                                )}
                                                {#if payment.description}
                                                    <span class="payment-desc"
                                                        >({payment.description})</span
                                                    >
                                                {/if}
                                            </div>
                                        {/each}
                                    </div>
                                {/if}
                            </div>
                        {/each}
                    </div>
                {/if}
            </section>

            <!-- Installment Plans Section -->
            <section class="pending-section">
                <div class="section-header">
                    <h2 class="section-title">{$t.pending.installmentPlans}</h2>
                    <div class="section-total" style="color: var(--warning)">
                        {formatAmount(totalInstallments)}
                    </div>
                </div>

                {#if installmentPlans.length === 0}
                    <div class="empty-state">
                        <p>{$t.pending.noActiveInstallments}</p>
                    </div>
                {:else}
                    <div class="entries-list">
                        {#each installmentPlans as entry}
                            <div class="entry-card">
                                <div class="entry-header">
                                    <div class="entry-info">
                                        <div class="counterparty-name">
                                            {entry.counterparty_name}
                                        </div>
                                        {#if entry.primary_transaction_description}
                                            <div class="entry-description">
                                                {entry.primary_transaction_description}
                                            </div>
                                        {/if}
                                    </div>
                                    <div
                                        class="entry-amount"
                                        style="color: var(--warning)"
                                    >
                                        {formatAmount(entry.pending_amount)}
                                    </div>
                                </div>
                                <div class="entry-details">
                                    <span class="entry-type"
                                        >{getLinkTypeLabel(
                                            entry.link_type,
                                        )}</span
                                    >
                                    <span class="entry-date">
                                        {formatDate(entry.created_at)}
                                    </span>
                                    <span
                                        class="entry-status"
                                        style="color: {getStatusColor(
                                            entry.status,
                                        )}"
                                    >
                                        {getStatusLabel(entry.status)}
                                    </span>
                                </div>
                                {#if entry.notes}
                                    <div class="entry-notes">{entry.notes}</div>
                                {/if}
                                {#if entry.linked_transactions && entry.linked_transactions.length > 0}
                                    <div class="payments-received">
                                        <div class="payments-header">
                                            {$t.pending.chargesReceived}:
                                        </div>
                                        {#each entry.linked_transactions as payment}
                                            <div class="payment-item">
                                                ✅ {payment.date
                                                    ? formatDate(payment.date)
                                                    : "N/A"} - {formatAmount(
                                                    payment.amount,
                                                )}
                                                {#if payment.description}
                                                    <span class="payment-desc"
                                                        >({payment.description})</span
                                                    >
                                                {/if}
                                            </div>
                                        {/each}
                                    </div>
                                {/if}
                            </div>
                        {/each}
                    </div>
                {/if}
            </section>
        {/if}
    </div>
</div>

<style>
    .pending-screen {
        display: flex;
        flex-direction: column;
        height: 100%;
        overflow: hidden;
    }

    /* .screen-header, .header-content, .screen-title moved to global panes.css */

    .refresh-btn {
        margin-left: auto;
        padding: var(--space-2) var(--space-4);
        background-color: var(--surface-elevated);
        color: var(--text-primary);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-semibold);
        cursor: pointer;
        transition: all var(--transition-base);
    }

    .refresh-btn:hover:not(:disabled) {
        background-color: var(--border-light);
    }

    .refresh-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .screen-content {
        flex: 1;
        overflow: auto;
        padding: var(--space-6) var(--space-8);
    }

    .loading-state,
    .error-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        height: 100%;
        gap: var(--space-4);
    }

    .spinner {
        width: 48px;
        height: 48px;
        border: 4px solid var(--border);
        border-top-color: var(--accent);
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }

    .error-message {
        color: var(--error);
        font-size: var(--font-size-lg);
        margin: 0;
    }

    .retry-btn {
        padding: var(--space-2) var(--space-4);
        background-color: var(--accent);
        color: white;
        border: none;
        border-radius: var(--radius-md);
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-semibold);
        cursor: pointer;
        transition: all var(--transition-base);
    }

    .retry-btn:hover {
        background-color: #0056b3;
    }

    .pending-section {
        margin-bottom: var(--space-8);
    }

    .section-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: var(--space-4);
        padding-bottom: var(--space-3);
        border-bottom: 2px solid var(--border);
    }

    .section-title {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-bold);
        color: var(--text-primary);
        margin: 0;
    }

    .section-total {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-bold);
        font-variant-numeric: tabular-nums;
    }

    .empty-state {
        text-align: center;
        padding: var(--space-8);
        color: var(--text-secondary);
        font-size: var(--font-size-lg);
    }

    .entries-list {
        display: flex;
        flex-direction: column;
        gap: var(--space-4);
    }

    .entry-card {
        background-color: var(--surface-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        padding: var(--space-4);
        transition: all var(--transition-base);
    }

    .entry-card:hover {
        box-shadow: var(--shadow-md);
        transform: translateY(-1px);
    }

    .entry-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: var(--space-3);
    }

    .entry-info {
        display: flex;
        flex-direction: column;
        gap: var(--space-1);
    }

    .counterparty-name {
        font-size: var(--font-size-lg);
        font-weight: var(--font-weight-bold);
        color: var(--text-primary);
    }

    .entry-description {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .entry-amount {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-bold);
        font-variant-numeric: tabular-nums;
    }

    .entry-details {
        display: flex;
        gap: var(--space-4);
        margin-bottom: var(--space-3);
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .entry-type {
        font-weight: var(--font-weight-semibold);
    }

    .entry-status {
        font-weight: var(--font-weight-semibold);
        text-transform: uppercase;
        font-size: var(--font-size-xs);
    }

    .entry-notes {
        margin-bottom: var(--space-3);
        padding: var(--space-2) var(--space-3);
        background-color: var(--surface);
        border-radius: var(--radius-sm);
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        font-style: italic;
    }

    .payments-received {
        margin-bottom: var(--space-3);
        padding: var(--space-3);
        background-color: var(--surface);
        border-radius: var(--radius-sm);
    }

    .payments-header {
        font-size: var(--font-size-sm);
        font-weight: var(--font-weight-semibold);
        color: var(--text-secondary);
        margin-bottom: var(--space-2);
    }

    .payment-item {
        font-size: var(--font-size-sm);
        color: var(--text-primary);
        margin-bottom: var(--space-1);
    }

    .payment-desc {
        color: var(--text-secondary);
    }
</style>
