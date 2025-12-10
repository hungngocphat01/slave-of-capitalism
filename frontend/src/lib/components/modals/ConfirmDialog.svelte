<script lang="ts">
    interface Props {
        message: string;
        onConfirm: () => void;
        onCancel: () => void;
    }

    let { message, onConfirm, onCancel }: Props = $props();

    function handleConfirm() {
        onConfirm();
    }

    function handleCancel() {
        onCancel();
    }

    function handleKeyDown(event: KeyboardEvent) {
        if (event.key === "Escape") {
            handleCancel();
        } else if (event.key === "Enter") {
            handleConfirm();
        }
    }
</script>

<div
    class="modal-backdrop"
    onclick={handleCancel}
    onkeydown={handleKeyDown}
    role="button"
    tabindex="0"
>
    <div
        class="modal dialog-modal"
        onclick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        tabindex="-1"
    >
        <div class="modal-content">
            <div class="dialog-message">{message}</div>
            <div class="form-actions right">
                <button class="btn secondary" onclick={handleCancel}
                    >Cancel</button
                >
                <button class="btn danger" onclick={handleConfirm} autofocus
                    >Delete</button
                >
            </div>
        </div>
    </div>
</div>

<style>
    /* Most styles are from modal.css and buttons.css */
    .dialog-modal {
        max-width: 450px;
    }

    .dialog-message {
        font-size: var(--font-size-base);
        color: var(--text-primary);
        margin-bottom: var(--space-6);
        line-height: 1.5;
        font-weight: 500;
    }
</style>
