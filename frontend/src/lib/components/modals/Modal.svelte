<script lang="ts">
    import { onMount } from "svelte";

    import { type Snippet } from "svelte";

    interface Props {
        title: string;
        onClose: () => void;
        children?: Snippet;
        footer?: Snippet;
    }

    let { title, onClose, children, footer }: Props = $props();

    let modalElement: HTMLDivElement;

    function handleBackdropClick(event: MouseEvent) {
        if (event.target === event.currentTarget) {
            onClose();
        }
    }

    function handleKeyDown(event: KeyboardEvent) {
        if (event.key === "Escape") {
            onClose();
        }
    }

    onMount(() => {
        document.addEventListener("keydown", handleKeyDown);
        return () => {
            document.removeEventListener("keydown", handleKeyDown);
        };
    });
</script>

<div class="modal-backdrop" onclick={handleBackdropClick} role="presentation">
    <div
        class="modal"
        bind:this={modalElement}
        onclick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
    >
        <div class="modal-header">
            <h3 class="modal-title">{title}</h3>
            <button class="close-button" onclick={onClose} aria-label="Close">
                ✕
            </button>
        </div>

        <div class="modal-content">
            {@render children?.()}
        </div>

        {#if footer}
            <div class="modal-footer">
                {@render footer()}
            </div>
        {/if}
    </div>
</div>

<style>
    /* Styles are now in src/styles/modal.css */
</style>
