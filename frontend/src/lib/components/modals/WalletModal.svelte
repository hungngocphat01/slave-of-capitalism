<script lang="ts">
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type { Wallet } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { showAlert } from "$lib/utils/dialog";

    interface Props {
        wallet?: Wallet | null;
        onClose: () => void;
        onSave: () => void;
    }

    let { wallet, onClose, onSave }: Props = $props();

    let name = $state(wallet?.name || "");
    let type = $state<"normal" | "credit">(
        (wallet?.wallet_type as "normal" | "credit") || "normal",
    );
    let emoji = $state(wallet?.emoji || "💰");
    let initialBalance = $state(wallet ? 0 : 0);
    let creditLimit = $state(Number(wallet?.credit_limit) || 0);

    let saving = $state(false);

    async function handleSave() {
        saving = true;
        try {
            const data = {
                name,
                wallet_type: type,
                initial_balance: initialBalance,
                credit_limit: creditLimit,
                emoji,
            };

            if (wallet) {
                const updateData = {
                    name,
                    wallet_type: type,
                    credit_limit: creditLimit,
                    emoji,
                };
                await api.wallets.update(wallet.id, updateData);
            } else {
                await api.wallets.create(data);
            }
            onSave();
            onClose();
        } catch (e: any) {
            console.error("Failed to save wallet:", e);
        } finally {
            saving = false;
        }
    }
</script>

<Modal title={wallet ? $t.wallets.editWallet : $t.wallets.addWallet} {onClose}>
    <div class="modal-form">
        <div class="form-group">
            <label for="name">{$t.wallets.name}</label>
            <input
                id="name"
                type="text"
                bind:value={name}
                placeholder={$t.wallets.walletNamePlaceholder}
            />
        </div>

        <div class="form-group">
            <label for="emoji">{$t.wallets.emoji}</label>
            <input
                id="emoji"
                type="text"
                bind:value={emoji}
                placeholder="💰"
                maxlength="2"
            />
        </div>

        <div class="form-group">
            <label for="type">{$t.common.type}</label>
            <select id="type" bind:value={type} disabled={!!wallet}>
                <option value="normal">{$t.wallets.normal}</option>
                <option value="credit">{$t.wallets.credit}</option>
            </select>
        </div>

        {#if type === "normal"}
            <div class="form-group">
                <label for="initial">{$t.wallets.initialBalance}</label>
                <input
                    id="initial"
                    type="number"
                    bind:value={initialBalance}
                    disabled={!!wallet}
                />
            </div>
        {:else}
            <div class="form-group">
                <label for="limit">{$t.wallets.creditLimit}</label>
                <input id="limit" type="number" bind:value={creditLimit} />
            </div>
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
            onclick={handleSave}
            disabled={saving}
        >
            {$t.common.save}
        </button>
    {/snippet}
</Modal>
