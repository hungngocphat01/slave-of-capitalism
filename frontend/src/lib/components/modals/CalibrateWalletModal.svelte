<script lang="ts">
    import { api } from "$lib/api/client";
    import type { Wallet } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { t } from "$lib/i18n";

    interface Props {
        wallet: Wallet;
        currentBalance: number;
        miscCategoryId: number; // Required
        onClose: () => void;
        onSuccess: () => void;
    }

    let { wallet, currentBalance, miscCategoryId, onClose, onSuccess }: Props =
        $props();

    let correctBalance = $state(currentBalance);
    let difference = $derived(correctBalance - currentBalance);
    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleCalibrate() {
        if (difference === 0) return;

        saving = true;
        error = null;

        try {
            await api.wallets.calibrate(
                wallet.id,
                correctBalance,
                miscCategoryId,
            );
            onSuccess();
            onClose();
        } catch (e) {
            console.error("Failed to calibrate wallet", e);
            error =
                e instanceof Error ? e.message : "Failed to calibrate wallet";
        } finally {
            saving = false;
        }
    }

    function formatCurrency(amount: number): string {
        return new Intl.NumberFormat("en-US", {
            style: "currency",
            currency: "JPY",
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
        }).format(amount);
    }
</script>

<Modal title={$t.transactions?.calibrate || "Calibrate Wallet"} {onClose}>
    {#if error}
        <div class="error-banner">
            {error}
        </div>
    {/if}

    <div class="calibration-form">
        <div class="info-box">
            <p class="info-label">
                {$t.transactions?.currentBalance || "Current Balance"}
            </p>
            <p class="info-value">{formatCurrency(currentBalance)}</p>
        </div>

        <div class="form-group">
            <label for="correct-balance">
                {$t.transactions?.correctBalance || "Correct Balance"}
            </label>
            <div class="input-wrapper">
                <span class="currency-symbol">¥</span>
                <input
                    id="correct-balance"
                    type="number"
                    bind:value={correctBalance}
                    step="1"
                />
            </div>
            <p class="help-text">
                {$t.transactions?.difference || "Difference"}:
                <span
                    class="diff-value"
                    class:positive={difference > 0}
                    class:negative={difference < 0}
                >
                    {difference > 0 ? "+" : ""}{formatCurrency(difference)}
                </span>
                <span class="action-text">
                    {#if difference > 0}
                        ({$t.transactions?.add || "add"})
                    {:else if difference < 0}
                        ({$t.transactions?.subtract || "subtract"})
                    {/if}
                </span>
            </p>
        </div>
    </div>

    {#snippet footer()}
        <button
            class="btn mac-btn secondary"
            onclick={onClose}
            disabled={saving}
        >
            {$t.common.cancel || "Cancel"}
        </button>
        <button
            class="btn mac-btn primary"
            onclick={handleCalibrate}
            disabled={difference === 0 || saving}
        >
            {saving
                ? $t.common.loading || "Loading..."
                : $t.transactions?.calibrate || "Calibrate"}
        </button>
    {/snippet}
</Modal>

<style>
    .input-wrapper {
        position: relative;
        display: flex;
        align-items: center;
    }

    .currency-symbol {
        position: absolute;
        left: var(--space-3);
        color: var(--text-tertiary);
        font-weight: 500;
        pointer-events: none;
    }

    /* Override for currency input */
    input[type="number"] {
        padding-left: var(--space-8);
        font-weight: 600;
        font-size: var(--font-size-lg);
    }

    .diff-value.positive {
        color: var(--inflow);
        font-weight: 600;
    }
    .diff-value.negative {
        color: var(--outflow);
        font-weight: 600;
    }
</style>
