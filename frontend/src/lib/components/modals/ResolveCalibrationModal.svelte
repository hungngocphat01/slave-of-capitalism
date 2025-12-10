<script lang="ts">
    import { api } from "$lib/api/client";
    import type {
        PopulatedTransaction,
        CategoryWithSubcategories,
        Wallet,
        Direction,
        Classification,
    } from "$lib/api/types";
    import Modal from "./Modal.svelte";
    import { t } from "$lib/i18n";

    interface Props {
        calibration: PopulatedTransaction;
        categories: CategoryWithSubcategories[];
        wallets: Wallet[];
        onClose: () => void;
        onSuccess: () => void;
    }

    let { calibration, categories, wallets, onClose, onSuccess }: Props =
        $props();

    const isNegative = calibration.amount < 0;
    const absAmount = Math.abs(calibration.amount);

    // Form state for new transaction
    let newTransaction = $state({
        date: new Date().toISOString().split("T")[0],
        wallet_id: calibration.wallet_id,
        direction: calibration.direction,
        amount: calibration.amount.toString(), // Keep as string for input binding
        classification: calibration.classification,
        description: "",
        category_id: null as number | null,
        subcategory_id: null as number | null,
    });

    let saving = $state(false);
    let error = $state<string | null>(null);

    async function handleResolve() {
        if (!newTransaction.amount || parseFloat(newTransaction.amount) <= 0) {
            error = $t.transactions.amountRequired || "Amount is required";
            return;
        }

        saving = true;
        error = null;

        try {
            await api.transactions.resolveCalibration(calibration.id, {
                date: newTransaction.date,
                wallet_id: newTransaction.wallet_id,
                direction: newTransaction.direction,
                amount: parseFloat(newTransaction.amount),
                classification: newTransaction.classification,
                description: newTransaction.description,
                category_id: newTransaction.category_id || undefined,
                subcategory_id: newTransaction.subcategory_id || undefined,
            });

            onSuccess();
            onClose();
        } catch (e) {
            console.error("Failed to resolve calibration", e);
            error =
                e instanceof Error
                    ? e.message
                    : "Failed to resolve calibration";
        } finally {
            saving = false;
        }
    }
</script>

<Modal
    title={$t.transactions.resolveCalibration || "Resolve Calibration"}
    {onClose}
>
    <div class="modal-content">
        {#if error}
            <div class="error-banner">
                {error}
            </div>
        {/if}

        <p class="instruction-text">
            {$t.transactions.resolveCalibrationDesc ||
                "Create the actual transaction that caused this discrepancy to replace the calibration."}
        </p>

        <div class="edit-fields">
            <!-- Basic Fields -->
            <div class="form-row">
                <div class="form-group">
                    <label for="date-input">{$t.common.date}</label>
                    <input
                        id="date-input"
                        type="date"
                        bind:value={newTransaction.date}
                    />
                </div>

                <div class="form-group">
                    <label for="type-select">{$t.common.type}</label>
                    <select
                        id="type-select"
                        value={newTransaction.classification}
                        onchange={(e) => {
                            const val = (e.target as HTMLSelectElement).value;
                            if (val === "income") {
                                newTransaction.classification = "income";
                                newTransaction.direction = "inflow";
                            } else {
                                newTransaction.classification = "expense";
                                newTransaction.direction = "outflow";
                            }
                        }}
                    >
                        <option value="expense">Expense</option>
                        <option value="income">Income</option>
                    </select>
                </div>
            </div>

            <div class="form-group">
                <label for="amount-input">{$t.common.amount}</label>
                <input
                    id="amount-input"
                    type="number"
                    step="0.01"
                    bind:value={newTransaction.amount}
                />
            </div>

            <div class="form-group">
                <label for="desc-input">{$t.common.description}</label>
                <input
                    id="desc-input"
                    type="text"
                    bind:value={newTransaction.description}
                    placeholder="Description..."
                />
            </div>

            <div class="form-group">
                <label for="category-select">{$t.common.category}</label>
                <select
                    id="category-select"
                    value={newTransaction.subcategory_id ||
                        (newTransaction.category_id
                            ? `cat_${newTransaction.category_id}`
                            : "")}
                    onchange={(e) => {
                        const value = (e.target as HTMLSelectElement).value;
                        if (!value) {
                            newTransaction.category_id = null;
                            newTransaction.subcategory_id = null;
                        } else if (value.startsWith("cat_")) {
                            newTransaction.category_id = parseInt(
                                value.replace("cat_", ""),
                            );
                            newTransaction.subcategory_id = null;
                        } else {
                            const subId = parseInt(value);
                            const sub = categories
                                .flatMap((c) => c.subcategories || [])
                                .find((s) => s.id === subId);
                            newTransaction.subcategory_id = subId;
                            newTransaction.category_id =
                                sub?.category_id || null;
                        }
                    }}
                >
                    <option value=""
                        >{$t.transactions.uncategorized ||
                            "Uncategorized"}</option
                    >
                    {#each categories as category}
                        {#if category.subcategories && category.subcategories.length > 0}
                            <optgroup label="{category.emoji} {category.name}">
                                {#each category.subcategories as sub}
                                    <option value={sub.id}>{sub.name}</option>
                                {/each}
                            </optgroup>
                        {:else}
                            <option value="cat_{category.id}"
                                >{category.emoji} {category.name}</option
                            >
                        {/if}
                    {/each}
                </select>
            </div>

            <div class="form-group">
                <label for="wallet">{$t.common.wallet}</label>
                <select
                    id="wallet"
                    bind:value={newTransaction.wallet_id}
                    disabled
                >
                    {#each wallets as wallet}
                        <option value={wallet.id}>{wallet.name}</option>
                    {/each}
                </select>
            </div>
        </div>
    </div>

    {#snippet footer()}
        <button
            class="btn mac-btn primary"
            onclick={handleResolve}
            disabled={saving}
        >
            {saving
                ? $t.common.loading || "Loading..."
                : $t.transactions.resolve || "Resolve"}
        </button>
        <button
            class="btn mac-btn secondary"
            onclick={onClose}
            disabled={saving}
        >
            {$t.common.cancel || "Cancel"}
        </button>
    {/snippet}
</Modal>
