<script lang="ts">
    import ContextMenu from "./ContextMenu.svelte";
    import type { Wallet } from "$lib/api/types";
    import { t } from "$lib/i18n";
    import { Pencil, ArrowsRightLeft, Scale, Trash } from "svelte-heros-v2";

    interface Props {
        wallet: Wallet;
        position: { x: number; y: number };
        onClose: () => void;
        onEdit: () => void;
        onDelete: () => void;
        onCalibrate: () => void;
        onTransfer: () => void;
    }

    let {
        wallet,
        position,
        onClose,
        onEdit,
        onDelete,
        onCalibrate,
        onTransfer,
    }: Props = $props();
</script>

<ContextMenu x={position.x} y={position.y} {onClose}>
    <div class="menu-header">
        <span class="menu-title">{wallet.name}</span>
    </div>

    <div class="menu-divider"></div>

    <button
        class="menu-item"
        onclick={() => {
            onEdit();
            onClose();
        }}
    >
        <span class="menu-icon">
            <Pencil size="16" />
        </span>
        <span class="menu-label">{$t.common.edit}</span>
    </button>

    <button
        class="menu-item"
        onclick={() => {
            onTransfer();
            onClose();
        }}
    >
        <span class="menu-icon">
            <ArrowsRightLeft size="16" />
        </span>
        <span class="menu-label">{$t.wallets.transfer}</span>
    </button>

    <button
        class="menu-item"
        onclick={() => {
            onCalibrate();
            onClose();
        }}
    >
        <span class="menu-icon">
            <Scale size="16" />
        </span>
        <span class="menu-label"
            >{$t.transactions?.calibrate || "Calibrate"}</span
        >
    </button>

    <div class="menu-divider"></div>

    <button
        class="menu-item destructive"
        onclick={() => {
            onDelete();
            onClose();
        }}
    >
        <span class="menu-icon">
            <Trash size="16" />
        </span>
        <span class="menu-label">{$t.common.delete}</span>
    </button>
</ContextMenu>

<style>
    /* Reusing global context menu styles from standard tables/panes usually,
       but for now we'll rely on the global CSS or inline if needed.
       The user's setup implies global styles for .context-menu exist in table.css
       so we just use those classes.
    */

    .menu-header {
        padding: var(--space-2) var(--space-3);
        font-size: var(--font-size-xs);
        color: var(--text-tertiary);
        font-weight: 600;
        text-transform: uppercase;
        /* Prevent selection */
        user-select: none;
    }

    /* Ensure destructive action is red if not globally defined */
    .menu-item.destructive {
        color: var(--error);
    }
    .menu-item.destructive:hover {
        background-color: rgba(255, 59, 48, 0.1);
    }
</style>
