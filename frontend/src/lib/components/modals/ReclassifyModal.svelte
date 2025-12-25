<script lang="ts">
    import Modal from "./Modal.svelte";
    import { t } from "$lib/i18n";
    import type { PopulatedTransaction, Classification } from "$lib/api/types";
    import { api } from "$lib/api/client";

    interface Props {
        transaction: PopulatedTransaction;
        onClose: () => void;
        onSave: (newClassification: Classification) => void;
    }

    let { transaction, onClose, onSave }: Props = $props();

    let selectedClassification = $state<Classification>(
        transaction.classification,
    );
    let saving = $state(false);
    let error = $state<string | null>(null);

    // Define allowed options based on direction
    const options = $derived(
        transaction.direction === "outflow"
            ? ([
                  {
                      value: "expense",
                      label: $t.transactionTypes.reclassify.expense,
                  },
                  {
                      value: "transfer",
                      label: $t.transactionTypes.reclassify.transfer,
                  },
                  {
                      value: "loan_repayment",
                      label: $t.transactionTypes.reclassify.loanRepayment,
                  },
                  {
                      value: "installmt_chrge",
                      label: $t.transactionTypes.reclassify.installmentCharge,
                  },
              ] as const)
            : ([
                  {
                      value: "income",
                      label: $t.transactionTypes.reclassify.income,
                  },
                  {
                      value: "transfer",
                      label: $t.transactionTypes.reclassify.transfer,
                  },
                  {
                      value: "borrow",
                      label: $t.transactionTypes.reclassify.borrow,
                  },
                  {
                      value: "debt_collection",
                      label: $t.transactionTypes.reclassify.debtCollection,
                  },
              ] as const),
    );

    async function handleSave() {
        if (selectedClassification === transaction.classification) {
            onClose();
            return;
        }

        saving = true;
        error = null;

        try {
            await api.transactions.reclassify(
                transaction.id,
                selectedClassification,
            );
            onSave(selectedClassification);
        } catch (e) {
            console.error(e);
        } finally {
            saving = false;
        }
    }
</script>

<Modal title={$t.transactionTypes.reclassify.title} {onClose}>
    {#if error}
        <div class="error-banner">{error}</div>
    {/if}

    <p class="instruction-text">
        {$t.transactionTypes.reclassify.desc}
        <strong
            >{transaction.direction === "outflow"
                ? $t.transactionTypes.outflow
                : $t.transactionTypes.inflow}</strong
        >
        {$t.transactionTypes.reclassify.transaction}.
    </p>

    <div class="option-list">
        {#each options as option}
            <label
                class="option-row"
                class:selected={selectedClassification === option.value}
            >
                <span class="option-label">{option.label}</span>
                <input
                    type="radio"
                    name="classification"
                    value={option.value}
                    bind:group={selectedClassification}
                />
            </label>
        {/each}
    </div>

    {#snippet footer()}
        <button
            class="btn mac-btn secondary"
            onclick={onClose}
            disabled={saving}>Cancel</button
        >
        <button
            class="btn mac-btn primary"
            onclick={handleSave}
            disabled={saving}
        >
            {saving ? "Saving..." : "Reclassify"}
        </button>
    {/snippet}
</Modal>
