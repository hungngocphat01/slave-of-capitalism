<script lang="ts">
    import { onMount } from "svelte";

    interface Props {
        x: number;
        y: number;
        onClose: () => void;
        children: any;
    }

    let { x, y, onClose, children }: Props = $props();

    let menuElement: HTMLDivElement;

    function handleClickOutside(event: MouseEvent) {
        if (menuElement && !menuElement.contains(event.target as Node)) {
            // Check if it's a right click (contextmenu event) - sometimes we want to allow re-opening elsewhere
            // But usually we just close.
            onClose();
        }
    }

    onMount(() => {
        // Delay adding event listener to avoid immediate close if initial click bubbles
        const timeout = setTimeout(() => {
            document.addEventListener("click", handleClickOutside);
            document.addEventListener("contextmenu", handleClickOutside);
        }, 100);

        return () => {
            clearTimeout(timeout);
            document.removeEventListener("click", handleClickOutside);
            document.removeEventListener("contextmenu", handleClickOutside);
        };
    });
</script>

<div
    class="context-menu"
    bind:this={menuElement}
    style="left: {x}px; top: {y}px;"
    role="menu"
    tabindex="-1"
>
    {@render children()}
</div>

<style>
    /* 
     * We assume global styles for .context-menu exist (e.g. in table.css or global CSS).
     * If not, we can define basic structure here, but the user mentioned reusing CSS.
     * I will include basic structural CSS that might be expected if global is missing or relies on this file.
     */
    .context-menu {
        position: fixed;
        background: white;
        border: 1px solid var(--border-light, #e5e5ea);
        border-radius: var(--radius-md, 8px);
        box-shadow: var(--shadow-lg, 0 10px 15px rgba(0, 0, 0, 0.1));
        z-index: 1000;
        min-width: 200px;
        padding: 4px 0;
        display: flex;
        flex-direction: column;
    }
</style>
