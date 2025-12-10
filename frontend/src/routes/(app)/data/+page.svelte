<script lang="ts">
    import { t } from "$lib/i18n";
    import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

    async function openPayPayImport() {
        try {
            console.log("Opening PayPay import wizard...");

            const webview = new WebviewWindow("paypay-import", {
                url: "/import/paypay",
                title: "PayPay Import Wizard",
                width: 1000,
                height: 700,
                resizable: true,
                minimizable: false,
                maximizable: false,
            });

            await webview.once("tauri://created", function () {
                console.log("Import wizard window created successfully");
            });

            await webview.once("tauri://error", function (e) {
                console.error("Failed to create window:", e);
            });
        } catch (error) {
            console.error("Error opening import wizard:", error);
            alert(`Failed to open import wizard: ${error}`);
        }
    }
</script>

<div class="mac-layout">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.nav.importExport}</h1>
        </div>
    </header>

    <div class="pane-content padded">
        <div class="import-options">
            <div
                class="import-card"
                role="button"
                tabindex="0"
                on:click={openPayPayImport}
                on:keydown={(e) => e.key === "Enter" && openPayPayImport()}
            >
                <div class="card-icon">📥</div>
                <h2>Import from PayPay</h2>
                <p>
                    Import transactions from PayPay CSV export with automatic
                    categorization based on your rules.
                </p>
                <button class="btn-primary">Start Import</button>
            </div>

            <div class="import-card disabled">
                <div class="card-icon">📤</div>
                <h2>Export Data</h2>
                <p>
                    Export your transactions and data for backup or analysis.
                    Coming soon.
                </p>
                <button class="btn-secondary" disabled>Coming Soon</button>
            </div>

            <div class="import-card disabled">
                <div class="card-icon">🔗</div>
                <h2>Other Imports</h2>
                <p>
                    Additional import options for other payment services will be
                    available in the future.
                </p>
                <button class="btn-secondary" disabled>Coming Soon</button>
            </div>
        </div>
    </div>
</div>

<style>
    .import-options {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
        gap: var(--space-6);
        padding: var(--space-4);
    }

    .import-card {
        background: var(--surface-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        padding: var(--space-6);
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
        transition: all var(--transition-base);
        cursor: pointer;
    }

    .import-card:not(.disabled):hover {
        border-color: var(--accent);
        box-shadow: var(--shadow-md);
        transform: translateY(-2px);
    }

    .import-card.disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .card-icon {
        font-size: 48px;
        margin-bottom: var(--space-4);
    }

    .import-card h2 {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-semibold);
        color: var(--text-primary);
        margin: 0 0 var(--space-3) 0;
    }

    .import-card p {
        font-size: var(--font-size-base);
        color: var(--text-secondary);
        margin: 0 0 var(--space-6) 0;
        line-height: 1.6;
        flex: 1;
    }

    .import-card button {
        width: 100%;
    }
</style>
