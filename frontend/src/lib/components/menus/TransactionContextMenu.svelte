<script lang="ts">
    import type { PopulatedTransaction } from "$lib/api/types";
    import ContextMenu from "./ContextMenu.svelte";
    import { t } from "$lib/i18n";
    import { api } from "$lib/api/client";
    import { showAlert, showConfirm } from "$lib/utils/dialog";
    import {
        CheckCircle,
        Link,
        Trash,
        ArrowsRightLeft,
        Banknotes,
        BuildingLibrary,
        InformationCircle,
        Tag,
        Eye,
        ArrowUturnLeft,
        Scale,
        Check,
        NoSymbol,
        CreditCard,
        ChevronRight,
    } from "svelte-heros-v2";

    interface Props {
        transaction: PopulatedTransaction;
        multipleSelected: boolean;
        position: { x: number; y: number };
        onClose: () => void;
        onDelete: () => void;
        onUpdate: () => void;
        onMarkAsSplit: () => void;
        onMarkAsLoan: () => void;
        onMarkAsDebt: () => void;
        onMarkAsInstallment: () => void;
        onLinkToEntry: () => void;
        onUnclassify: () => void;
        onViewDetails: () => void;
        onReclassify: () => void;
        onViewReimbursements: () => void;
        onIgnore: () => void;
        onUnignore: () => void;
        onResolveCalibration: () => void;
        onSelectMultiple: () => void;
        onMerge: () => void;
    }

    let {
        transaction,
        multipleSelected = false,
        position,
        onClose,
        onDelete,
        onUpdate,
        onMarkAsSplit,
        onMarkAsLoan,
        onMarkAsDebt,
        onMarkAsInstallment,
        onLinkToEntry,
        onUnclassify,
        onViewDetails,
        onReclassify,
        onViewReimbursements,
        onIgnore,
        onUnignore,
        onResolveCalibration,
        onSelectMultiple,
        onMerge,
    }: Props = $props();

    // Determine which menu items to show based on transaction type
    const canUnlink = $derived(
        !multipleSelected && transaction.is_linked_to_entry,
    );

    async function handleUnlink() {
        if (!transaction) return;

        const confirmed = await showConfirm(
            $t.transactions.unlinkConfirmMessage,
            $t.transactions.unlinkConfirmTitle,
        );

        if (confirmed) {
            try {
                await api.transactions.unlink(transaction.id);
                onUpdate();
                onClose();
            } catch (err) {
                console.error(err);
            }
        }
    }
    const canMarkAsSplit = $derived(
        !multipleSelected &&
            transaction.direction === "outflow" &&
            transaction.classification === "expense",
    );

    const canMarkAsLoan = $derived(
        !multipleSelected &&
            transaction.direction === "outflow" &&
            (transaction.classification === "lend" ||
                transaction.classification === "expense"),
    );

    const canMarkAsDebt = $derived(
        !multipleSelected &&
            transaction.direction === "inflow" &&
            (transaction.classification === "borrow" ||
                transaction.classification === "income"),
    );

    const canMarkAsInstallment = $derived(
        !multipleSelected &&
            transaction.direction === "outflow" &&
            transaction.wallet_type === "credit" &&
            transaction.classification === "expense",
    );

    const canLinkToEntry = $derived(
        transaction.classification === "debt_collection" ||
            transaction.classification === "loan_repayment" ||
            transaction.classification === "installmt_chrge" ||
            transaction.classification === "income", // Allow linking regular income (reimbursement)
    );

    const hasSpecialActions = $derived(
        canMarkAsSplit ||
            canMarkAsLoan ||
            canMarkAsDebt ||
            canMarkAsInstallment,
    );

    const hasLinkedEntry = $derived(!!transaction.linked_entry);

    function handleSeeReimbursements() {
        onViewReimbursements();
        onClose();
    }

    function handleReclassify() {
        onReclassify();
        onClose();
    }

    function handleDeleteClick() {
        onDelete();
        onClose();
    }
</script>

<ContextMenu x={position.x} y={position.y} {onClose}>
    {#if !multipleSelected}
        <button
            class="menu-item"
            onclick={() => {
                onSelectMultiple();
                onClose();
            }}
        >
            <span class="menu-icon">
                <CheckCircle size="16" />
            </span>
            <span class="menu-label">{$t.transactions.select}</span>
        </button>
    {:else}
        <button
            class="menu-item"
            onclick={() => {
                onMerge();
                onClose();
            }}
        >
            <span class="menu-icon">
                <Link size="16" />
            </span>
            <span class="menu-label">{$t.transactions.merge}</span>
        </button>
        <div class="menu-divider"></div>
    {/if}

    {#if hasSpecialActions}
        <div class="menu-divider"></div>

        <!-- Submenu Parent -->
        <div class="menu-item has-submenu">
            <span class="menu-icon">
                <Tag size="16" />
            </span>
            <span class="menu-label">{$t.transactions.markAs}</span>
            <span class="submenu-arrow">
                <ChevronRight size="14" />
            </span>

            <!-- Submenu Content -->
            <div class="submenu">
                {#if canMarkAsSplit}
                    <button
                        class="menu-item"
                        onclick={() => {
                            onMarkAsSplit();
                            onClose();
                        }}
                    >
                        <span class="menu-icon">
                            <ArrowsRightLeft size="16" />
                        </span>
                        <span class="menu-label"
                            >{$t.transactions.markAsSplit}</span
                        >
                    </button>
                {/if}

                {#if canMarkAsLoan}
                    <button
                        class="menu-item"
                        onclick={() => {
                            onMarkAsLoan();
                            onClose();
                        }}
                    >
                        <span class="menu-icon">
                            <Banknotes size="16" />
                        </span>
                        <span class="menu-label"
                            >{$t.transactions.markAsLoan}</span
                        >
                    </button>
                {/if}

                {#if canMarkAsDebt}
                    <button
                        class="menu-item"
                        onclick={() => {
                            onMarkAsDebt();
                            onClose();
                        }}
                    >
                        <span class="menu-icon">
                            <BuildingLibrary size="16" />
                        </span>
                        <span class="menu-label"
                            >{$t.transactions.markAsDebt}</span
                        >
                    </button>
                {/if}

                {#if canMarkAsInstallment}
                    <button
                        class="menu-item"
                        onclick={() => {
                            onMarkAsInstallment();
                            onClose();
                        }}
                    >
                        <span class="menu-icon">
                            <CreditCard size="16" />
                        </span>
                        <span class="menu-label"
                            >{$t.transactions.markAsInstallment}</span
                        >
                    </button>
                {/if}
            </div>
        </div>
    {/if}

    {#if (canLinkToEntry || hasLinkedEntry) && hasSpecialActions}
        <div class="menu-divider"></div>
    {/if}

    {#if canLinkToEntry}
        <button
            class="menu-item"
            onclick={() => {
                onLinkToEntry();
                onClose();
            }}
        >
            <span class="menu-icon">
                <Link size="16" />
            </span>
            <span class="menu-label">{$t.transactions.linkToEntry}</span>
        </button>
    {/if}

    {#if !multipleSelected}
        <button
            class="menu-item"
            onclick={() => {
                onViewDetails();
                onClose();
            }}
        >
            <span class="menu-icon">
                <InformationCircle size="16" />
            </span>
            <span class="menu-label">{$t.transactions.viewDetails}</span>
        </button>

        {#if !hasLinkedEntry}
            <button class="menu-item" onclick={handleReclassify}>
                <span class="menu-icon">
                    <Tag size="16" />
                </span>
                <span class="menu-label">{$t.transactions.reclassify}</span>
            </button>
        {/if}

        {#if hasLinkedEntry}
            <button class="menu-item" onclick={handleSeeReimbursements}>
                <span class="menu-icon">
                    <Eye size="16" />
                </span>
                <span class="menu-label"
                    >{$t.transactions.seeReimbursements}</span
                >
            </button>
            <button
                class="menu-item"
                onclick={() => {
                    onUnclassify();
                    onClose();
                }}
            >
                <span class="menu-icon">
                    <ArrowUturnLeft size="16" />
                </span>
                <span class="menu-label">{$t.transactions.unclassify}</span>
            </button>
        {/if}

        <div class="menu-divider"></div>

        {#if transaction.is_calibration}
            <button
                class="menu-item"
                onclick={() => {
                    onResolveCalibration();
                    onClose();
                }}
            >
                <span class="menu-icon">
                    <Scale size="16" />
                </span>
                <span class="menu-label"
                    >{$t.transactions.resolveCalibration}</span
                >
            </button>
        {/if}
    {/if}

    {#if transaction.is_ignored}
        <button
            class="menu-item"
            onclick={() => {
                onUnignore();
                onClose();
            }}
        >
            <span class="menu-icon">
                <Check size="16" />
            </span>
            <span class="menu-label">{$t.transactions.unignore}</span>
        </button>
    {:else}
        <button
            class="menu-item"
            onclick={() => {
                onIgnore();
                onClose();
            }}
        >
            <span class="menu-icon">
                <NoSymbol size="16" />
            </span>
            <span class="menu-label">{$t.transactions.ignore}</span>
        </button>
    {/if}

    <div class="menu-divider"></div>

    {#if canUnlink}
        <button class="menu-item" onclick={handleUnlink}>
            <span class="menu-icon">
                <iconify-icon icon="mdi:link-variant-off"></iconify-icon>
            </span>
            <span class="menu-label">{$t.transactions.unlinkTransaction}</span>
        </button>
    {/if}

    <button class="menu-item" onclick={handleDeleteClick}>
        <span class="menu-icon">
            <Trash size="16" />
        </span>
        <span class="menu-label">{$t.common.delete}</span>
    </button>
</ContextMenu>

<style>
    /* 
     * Specific item styles can remain here or also be global.
     * Assuming .menu-item, .menu-icon, .menu-label, .menu-divider are global in table.css
     * If they were internal to the old ContextMenu, I should move them to global or the new ContextMenu.
     * Let's check if they were in the old file... looks like they were NOT in the old file "Styles are now in src/styles/table.css"
     */
    .has-submenu {
        position: relative;
    }

    .submenu {
        display: none;
        position: absolute;
        left: 100%;
        top: -4px;
        background-color: var(--surface-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        box-shadow: var(--shadow-lg);
        padding: var(--space-2);
        min-width: 220px;
        z-index: 1001;
    }

    .has-submenu:hover .submenu {
        display: flex;
        flex-direction: column;
    }

    .submenu-arrow {
        color: var(--text-tertiary);
        display: flex;
        align-items: center;
    }
</style>
