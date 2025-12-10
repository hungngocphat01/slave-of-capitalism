<script lang="ts">
    import Modal from "./Modal.svelte";
    import type { Wallet } from "$lib/api/types";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";

    interface Props {
        wallets: Wallet[];
        fromWalletId?: number;
        onClose: () => void;
        onSave: () => void;
    }

    let { wallets, fromWalletId, onClose, onSave }: Props = $props();

    let form = $state({
        date: new Date().toISOString().split("T")[0],
        time: "",
        from_wallet_id: fromWalletId || 0,
        to_wallet_id: 0,
        amount: "",
        description: "Transfer",
    });

    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleSave() {
        if (!form.from_wallet_id || !form.to_wallet_id || !form.amount) {
            error = "Please fill in all fields";
            return;
        }

        if (form.from_wallet_id === form.to_wallet_id) {
            error = "Source and destination wallets must be different";
            return;
        }

        saving = true;
        error = null;

        try {
            await api.wallets.transfer({
                date: form.date,
                time: form.time || undefined,
                from_wallet_id: form.from_wallet_id,
                to_wallet_id: form.to_wallet_id,
                amount: parseFloat(form.amount),
                description: form.description,
            });
            onSave();
        } catch (e) {
            console.error(e);
            error = "Failed to process transfer";
        } finally {
            saving = false;
        }
    }
</script>

<Modal title={$t.transferModal.title} {onClose}>
    {#if error}
        <div class="error-banner">{error}</div>
    {/if}

    <p class="instruction-text">
        {$t.transferModal.desc}
    </p>

    <div class="form-row">
        <div class="form-group">
            <label for="date-input">{$t.common.date}</label>
            <input id="date-input" type="date" bind:value={form.date} />
        </div>
        <div class="form-group">
            <label for="time-input">{$t.common.time}</label>
            <input id="time-input" type="time" bind:value={form.time} />
        </div>
    </div>

    <div class="transfer-arrow-visual">
        <div class="wallet-select-group">
            <label for="from-wallet">{$t.transferModal.from}</label>
            <select id="from-wallet" bind:value={form.from_wallet_id}>
                <option value={0} disabled
                    >{$t.transferModal.selectWallet}</option
                >
                {#each wallets as wallet}
                    <option value={wallet.id}
                        >{wallet.name} (¥{wallet.current_balance.toLocaleString()})</option
                    >
                {/each}
            </select>
        </div>

        <div class="arrow">↓</div>

        <div class="wallet-select-group">
            <label for="to-wallet">{$t.transferModal.to}</label>
            <select id="to-wallet" bind:value={form.to_wallet_id}>
                <option value={0} disabled
                    >{$t.transferModal.selectWallet}</option
                >
                {#each wallets as wallet}
                    {#if wallet.id !== form.from_wallet_id}
                        <option value={wallet.id}>{wallet.name}</option>
                    {/if}
                {/each}
            </select>
        </div>
    </div>

    <div class="form-group">
        <label for="amount-input">{$t.common.amount}</label>
        <input
            id="amount-input"
            type="number"
            step="0.01"
            placeholder="0"
            bind:value={form.amount}
            class="amount-input"
        />
    </div>

    <div class="form-group">
        <label for="desc-input">Description</label>
        <input id="desc-input" type="text" bind:value={form.description} />
    </div>

    {#snippet footer()}
        <button class="mac-btn secondary" onclick={onClose} disabled={saving}
            >{$t.common.cancel}</button
        >
        <button class="mac-btn primary" onclick={handleSave} disabled={saving}>
            {saving ? "Transferring..." : $t.transferModal.transferMoney}
        </button>
    {/snippet}
</Modal>

<style>
    .transfer-arrow-visual {
        background: var(--surface);
        padding: var(--space-3);
        border-radius: var(--radius-md);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--space-2);
        border: 1px solid var(--border-light);
        margin-bottom: var(--space-4);
    }

    .wallet-select-group {
        width: 100%;
        display: flex;
        flex-direction: column;
        gap: var(--space-1);
    }

    .wallet-select-group label {
        font-size: var(--font-size-xs);
        color: var(--text-tertiary);
    }

    .arrow {
        color: var(--text-tertiary);
        font-size: 20px;
        line-height: 1;
    }

    .amount-input {
        font-size: var(--font-size-lg);
        font-weight: 600;
        text-align: right;
        color: var(--text-primary);
    }
</style>
