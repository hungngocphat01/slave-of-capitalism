<script lang="ts">
    import { onMount } from "svelte";
    import { getCurrentWindow } from "@tauri-apps/api/window";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import { settings } from "$lib/stores/settings";
    import type { Wallet, BalanceAudit } from "$lib/api/types";

    let wallets = $state<Wallet[]>([]);
    let audits = $state<BalanceAudit[]>([]);
    let loading = $state(true);

    // Current Stats for Snapshot
    let currentDebts = 0;
    let currentOwed = 0;

    onMount(async () => {
        await loadData();
    });

    async function loadData() {
        loading = true;
        try {
            const [wals, auds, pending] = await Promise.all([
                api.wallets.getAll(),
                api.wallets.getAudits(),
                api.linkedEntries.getPending(),
            ]);

            wallets = wals;
            audits = auds;

            // Calculate current debts/owed
            currentDebts = 0;
            currentOwed = 0;
            for (const entry of pending) {
                if (entry.link_type === "debt") {
                    currentDebts += entry.pending_amount;
                } else if (
                    entry.link_type === "loan" ||
                    entry.link_type === "split_payment"
                ) {
                    currentOwed += entry.pending_amount;
                }
            }
        } catch (e) {
            console.error("Failed to load audit data", e);
        } finally {
            loading = false;
        }
    }

    async function takeSnapshot() {
        if (
            !confirm(
                "Record current balances as audit snapshot for today? Existing snapshot for today will be overwritten.",
            )
        )
            return;

        try {
            const today = new Date().toISOString().split("T")[0];

            // Server-side audit (no balances sent)
            await api.wallets.createAudit({
                date: today,
            });

            await loadData();
        } catch (e) {
            alert("Failed to take snapshot: " + e);
        }
    }

    function closeWindow() {
        getCurrentWindow().close();
    }

    function formatDate(dateStr: string) {
        const d = new Date(dateStr);
        const day = d.getDate().toString().padStart(2, "0");
        const dayName = d.toLocaleDateString("en-US", { weekday: "short" });
        return `${day} (${dayName})`;
    }

    function formatCurrency(amount: number) {
        if (amount === undefined || amount === null) return "-";
        return new Intl.NumberFormat("en-US", {
            style: "decimal",
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
        }).format(amount);
    }
</script>

<div class="app-layout">
    <header class="pane-header">
        <h2 class="screen-title">Balance Audit</h2>
    </header>

    <div class="pane-content padded">
        {#if loading}
            <div class="loading">Loading...</div>
        {:else}
            <div class="table-container">
                <table>
                    <thead>
                        <tr>
                            <th class="sticky-col">Item</th>
                            {#each audits as audit}
                                <th class="text-right date-col"
                                    >{formatDate(audit.date)}</th
                                >
                            {/each}
                        </tr>
                    </thead>
                    <tbody>
                        <!-- Wallets -->
                        {#each wallets as wallet}
                            <tr class="hover:bg-gray-50 transition-colors">
                                <td
                                    class="p-3 border-b flex items-center gap-2 sticky left-0 bg-white z-10 shadow-[2px_0_4px_-2px_rgba(0,0,0,0.1)]"
                                >
                                    <span class="emoji"
                                        >{wallet.emoji || "👛"}</span
                                    >
                                    <span>{wallet.name}</span>
                                    {#if wallet.wallet_type === "credit"}
                                        <span class="wallet-type-badge credit">
                                            {$t.wallets.credit}
                                        </span>
                                    {/if}
                                </td>
                                {#each audits as audit}
                                    <td
                                        class="p-3 border-b text-right font-medium"
                                    >
                                        {formatCurrency(
                                            audit.balances[
                                                wallet.id.toString()
                                            ] ?? 0,
                                        )}
                                    </td>
                                {/each}
                            </tr>
                        {/each}

                        <!-- Divider -->
                        <tr class="divider-row"
                            ><td colspan={audits.length + 1}></td></tr
                        >

                        <!-- Debts Row -->
                        <tr>
                            <td
                                class="p-3 border-b text-gray-500 sticky left-0 bg-white z-10 shadow-[2px_0_4px_-2px_rgba(0,0,0,0.1)]"
                                >Debts</td
                            >
                            {#each audits as audit}
                                <td
                                    class="p-3 border-b text-right text-gray-500"
                                >
                                    {formatCurrency(audit.debts)}
                                </td>
                            {/each}
                        </tr>

                        <!-- Owed Row -->
                        <tr>
                            <td
                                class="p-3 border-b text-gray-500 sticky left-0 bg-white z-10 shadow-[2px_0_4px_-2px_rgba(0,0,0,0.1)]"
                                >Owed</td
                            >
                            {#each audits as audit}
                                <td
                                    class="p-3 border-b text-right text-green-500"
                                >
                                    {formatCurrency(audit.owed)}
                                </td>
                            {/each}
                        </tr>

                        <!-- Divider -->
                        <tr class="divider-row"
                            ><td colspan={audits.length + 1}></td></tr
                        >

                        <!-- Net Position Row -->
                        <tr class="font-bold bg-secondary/5">
                            <td
                                class="p-3 border-b text-secondary sticky left-0 bg-white z-10 shadow-[2px_0_4px_-2px_rgba(0,0,0,0.1)]"
                            >
                                {$t.wallets.netPosition}
                            </td>
                            {#each audits as audit}
                                <td class="p-3 border-b text-right text-lg">
                                    {formatCurrency(audit.net_position)}
                                </td>
                            {/each}
                        </tr>
                    </tbody>
                </table>
            </div>
        {/if}
    </div>

    <footer
        class="pane-footer modal-footer"
        style="justify-content: space-between;"
    >
        <button class="btn btn-secondary" onclick={takeSnapshot}>
            Take Snapshot
        </button>
        <button class="btn btn-primary" onclick={closeWindow}> Close </button>
    </footer>
</div>

<style>
    .app-layout {
        display: flex;
        flex-direction: column;
        height: 100vh;
        background: var(--background);
        color: var(--text-primary);
    }

    /* pane-header, pane-content, pane-footer are global now usually, but let's keep basic layout */
    /* Assuming panes.css handles pane-header styling if we used correct classes. 
       Let's check if we should remove specific header styling too.
       For now, let's focus on table. */

    .pane-header {
        padding: 16px 24px;
        border-bottom: 1px solid var(--border);
        background: var(--surface);
    }

    .screen-title {
        margin: 0;
        font-size: 18px;
        font-weight: 600;
    }

    .pane-content {
        flex: 1;
        overflow: hidden;
        position: relative;
    }

    .loading {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100%;
        color: var(--text-secondary);
    }

    /* Table styles removed as they are global now */

    .sticky-col {
        position: sticky;
        left: 0;
        z-index: 5;
        border-right: 1px solid var(--border);
        font-weight: 500;
        min-width: 180px;
        background: var(
            --surface
        ); /* Ensure background to cover scrolling content */
    }

    th.sticky-col {
        z-index: 15; /* Higher than normal th z-index 10 */
        background: var(--surface-translucent, var(--surface));
    }

    .text-right {
        text-align: right;
    }

    .font-bold {
        font-weight: 600;
    }

    .wallet-type-badge {
        font-size: 10px;
        text-transform: uppercase;
        padding: 2px 6px;
        border-radius: 4px;
        font-weight: 600;
        margin-left: 6px;
        display: inline-block;
        white-space: nowrap;
    }

    .wallet-type-badge.credit {
        background: rgba(255, 149, 0, 0.1);
        color: var(--warning);
    }

    .divider-row td {
        background: var(--surface-hover);
        height: 4px;
        padding: 0;
        border: none;
    }

    .pane-footer {
        padding: 16px;
        border-top: 1px solid var(--border);
        display: flex;
        background: var(--surface);
    }

    /* Button styles - rely on global buttons.css?
       We see btn, btn-primary etc usually in buttons.css
       Let's keep them if unsure, or check if buttons.css defines them.
       It was imported in layout. */

    /* Assuming buttons.css covers .btn, .btn-primary, .btn-secondary */
</style>
