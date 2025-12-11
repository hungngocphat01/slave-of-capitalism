<script lang="ts">
    import "../../app.css";
    import "../../styles/typography.css";
    import "../../styles/buttons.css";
    import "../../styles/forms.css";
    import "../../styles/table.css";
    import "../../styles/modal.css";
    import "../../styles/panes.css";
    import { page } from "$app/stores";
    import { t } from "$lib/i18n";

    const navItems = [
        { path: "/", label: () => $t.nav.entry, icon: "📊" },
        { path: "/summary", label: () => $t.nav.summary, icon: "📈" },
        { path: "/wallets", label: () => $t.nav.wallets, icon: "💰" },
        { path: "/pending", label: () => $t.nav.pending, icon: "⏳" },
        { path: "/categories", label: () => $t.nav.categories, icon: "📁" },
    ];

    function handleKeydown(event: KeyboardEvent) {
        // Global shortcut: Ctrl+K to insert "000" in active input
        if (event.ctrlKey && event.key.toLowerCase() === "k") {
            const target = document.activeElement;

            // Check if target is an input or textarea and writable
            if (
                target &&
                (target.tagName === "INPUT" || target.tagName === "TEXTAREA") &&
                !(target as HTMLInputElement).readOnly &&
                !(target as HTMLInputElement).disabled
            ) {
                event.preventDefault();
                const input = target as HTMLInputElement | HTMLTextAreaElement;

                let start = input.selectionStart;
                let end = input.selectionEnd;

                // Workaround for type="number": selectionStart is always null
                // We temporarily switch to text to get the cursor position
                if (
                    input.tagName === "INPUT" &&
                    (input as HTMLInputElement).type === "number"
                ) {
                    const numberInput = input as HTMLInputElement;
                    numberInput.type = "text";
                    start = numberInput.selectionStart;
                    end = numberInput.selectionEnd;
                    numberInput.type = "number";
                }

                const value = input.value;
                const safeStart = start ?? value.length; // Default to end if still null
                const safeEnd = end ?? value.length;

                // Insert "000"
                const newValue =
                    value.substring(0, safeStart) +
                    "000" +
                    value.substring(safeEnd);
                input.value = newValue;

                // Dispatch input event to verify binding updates/UI reaction
                input.dispatchEvent(new Event("input", { bubbles: true }));

                // Attempt to restore cursor position (works for text, tricky for number)
                if (input.type !== "number") {
                    input.selectionStart = input.selectionEnd = safeStart + 3;
                }
            }
        }
    }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="app-layout">
    <!-- Sidebar -->
    <aside class="sidebar">
        <div class="sidebar-header">
            <h1 class="app-title">
                {$t.appTitle.first}<br />{$t.appTitle.second}
            </h1>
        </div>

        <nav class="sidebar-nav">
            {#each navItems as item}
                <a
                    href={item.path}
                    class="nav-item"
                    class:active={$page.url.pathname === item.path}
                >
                    <span class="nav-icon">{item.icon}</span>
                    <span class="nav-label">{item.label()}</span>
                </a>
            {/each}
        </nav>

        <div class="sidebar-footer">
            <a
                href="/data"
                class="nav-item"
                class:active={$page.url.pathname === "/data"}
            >
                <span class="nav-icon">💾</span>
                <span class="nav-label">{$t.nav.importExport}</span>
            </a>

            <a
                href="/settings"
                class="nav-item"
                class:active={$page.url.pathname === "/settings"}
            >
                <span class="nav-icon">⚙️</span>
                <span class="nav-label">{$t.nav.settings}</span>
            </a>
        </div>
    </aside>

    <!-- Main Content -->
    <main class="main-content">
        <slot />
    </main>
</div>

<style>
    /* Styles are now in src/styles/panes.css and src/app.css */
</style>
