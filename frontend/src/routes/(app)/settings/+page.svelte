<script lang="ts">
    import { onMount } from "svelte";
    import { settings, Language } from "$lib/stores/settings";
    import { t } from "$lib/i18n";
    import { config } from "$lib/api/config";

    let currentSettings = $state({ ...$settings });
    let customCurrency = $state("");
    let showCustomInput = $state(false);
    let saveMessage = $state("");
    let errorMessage = $state("");

    // Database path state
    let databasePath = $state("");
    let defaultDatabasePath = $state("");
    let isChangingDatabase = $state(false);

    // Advanced section state
    let showAdvanced = $state(false);

    // Port configuration state
    let portMode = $state<"random" | "custom">("random");
    let customPort = $state("");
    let currentPort = $state(0);

    const commonCurrencies = [
        { symbol: "$", name: "USD" },
        { symbol: "¥", name: "JPY/CNY" },
        { symbol: "€", name: "EUR" },
        { symbol: "£", name: "GBP" },
        { symbol: "₫", name: "VND" },
        { symbol: "₹", name: "INR" },
        { symbol: "₩", name: "KRW" },
        { symbol: "R$", name: "BRL" },
    ];

    onMount(async () => {
        try {
            // Load current database path from Tauri
            databasePath = await config.getDatabasePath();
            defaultDatabasePath = await config.getDefaultDatabasePath();
            currentSettings.databasePath = databasePath;

            // Load current port configuration
            currentPort = await config.getBackendPort();
            const portModeConfig = await config.get("app", "port_mode");
            portMode = portModeConfig === "custom" ? "custom" : "random";
            if (portMode === "custom") {
                customPort = currentPort.toString();
            }
        } catch (error) {
            console.error("Failed to load configuration:", error);
            errorMessage = "Failed to load configuration";
        }
    });

    function selectCurrency(symbol: string) {
        currentSettings.currency = symbol;
        showCustomInput = false;
        customCurrency = "";
    }

    function useCustomCurrency() {
        if (customCurrency.trim()) {
            currentSettings.currency = customCurrency.trim();
            showCustomInput = false;
        }
    }

    function handleSave() {
        settings.set(currentSettings);
        saveMessage = $t.settings.settingsSaved;
        setTimeout(() => {
            saveMessage = "";
        }, 3000);
    }

    async function handleChangeDatabasePath() {
        try {
            const selectedPath = await config.pickDatabaseFile();
            if (selectedPath) {
                isChangingDatabase = true;
                await config.setDatabasePath(selectedPath);
                databasePath = selectedPath;
                saveMessage = $t.settings.dbUpdated;

                setTimeout(() => {
                    saveMessage = "";
                }, 3000);
            }
        } catch (error) {
            console.error("Failed to change database path:", error);
            errorMessage = "Failed to change database path: " + error;
            setTimeout(() => {
                errorMessage = "";
            }, 5000);
        } finally {
            isChangingDatabase = false;
        }
    }

    async function handleResetDatabasePath() {
        try {
            isChangingDatabase = true;
            await config.setDatabasePath(defaultDatabasePath);
            databasePath = defaultDatabasePath;
            saveMessage = $t.settings.dbReset;

            setTimeout(() => {
                saveMessage = "";
            }, 3000);
        } catch (error) {
            console.error("Failed to reset database path:", error);
            errorMessage = "Failed to reset database path: " + error;
            setTimeout(() => {
                errorMessage = "";
            }, 5000);
        } finally {
            isChangingDatabase = false;
        }
    }

    async function handleSavePort() {
        try {
            if (portMode === "custom") {
                const port = parseInt(customPort);
                if (isNaN(port) || port < 1024 || port > 65535) {
                    errorMessage = $t.settings.portError;
                    setTimeout(() => (errorMessage = ""), 5000);
                    return;
                }
                await config.set("app", "port", port.toString());
                await config.set("app", "port_mode", "custom");
            } else {
                await config.remove("app", "port");
                await config.set("app", "port_mode", "random");
            }
            saveMessage = $t.settings.portSaved;
            setTimeout(() => (saveMessage = ""), 5000);
        } catch (error) {
            console.error("Failed to save port settings:", error);
            errorMessage = "Failed to save port settings: " + error;
            setTimeout(() => (errorMessage = ""), 5000);
        }
    }
</script>

<div class="mac-layout">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.settings.title}</h1>
        </div>
    </header>

    <div class="pane-content padded">
        {#if saveMessage}
            <div class="system-banner">
                <p>✓ {saveMessage}</p>
            </div>
        {/if}

        <div class="settings-content">
            <!-- Currency Settings -->
            <section class="settings-section">
                <h3>{$t.settings.currency}</h3>

                <div class="currency-grid">
                    {#each commonCurrencies as curr}
                        <button
                            class="currency-button"
                            class:selected={currentSettings.currency ===
                                curr.symbol && !showCustomInput}
                            onclick={() => selectCurrency(curr.symbol)}
                        >
                            <span class="currency-symbol">{curr.symbol}</span>
                            <span class="currency-name">{curr.name}</span>
                        </button>
                    {/each}

                    <button
                        class="currency-button custom"
                        class:selected={showCustomInput}
                        onclick={() => {
                            showCustomInput = true;
                        }}
                    >
                        <span class="currency-symbol">⊕</span>
                        <span class="currency-name">Custom</span>
                    </button>
                </div>

                {#if showCustomInput}
                    <div class="custom-currency-input">
                        <input
                            type="text"
                            bind:value={customCurrency}
                            placeholder={$t.settings.currencyPlaceholder}
                            maxlength="5"
                        />
                        <button
                            class="btn btn-primary"
                            onclick={useCustomCurrency}
                        >
                            {$t.common.confirm}
                        </button>
                    </div>
                {/if}

                <div class="current-selection">
                    <span>{$t.common.amount} example:</span>
                    <strong
                        >{currentSettings.currency}1,234{currentSettings.decimals >
                        0
                            ? "." + "0".repeat(currentSettings.decimals)
                            : ""}</strong
                    >
                </div>
            </section>

            <!-- Decimal Places -->
            <section class="settings-section">
                <h3>{$t.settings.decimals}</h3>

                <div class="decimals-selector">
                    {#each [0, 1, 2] as dec}
                        <button
                            class="decimal-button"
                            class:selected={currentSettings.decimals === dec}
                            onclick={() => {
                                currentSettings.decimals = dec;
                            }}
                        >
                            {dec}
                            {dec === 1 ? "digit" : "digits"}
                        </button>
                    {/each}
                </div>
            </section>

            <!-- Language -->
            <section class="settings-section">
                <h3>{$t.settings.language}</h3>

                <div class="language-selector">
                    <button
                        class="language-button"
                        class:selected={currentSettings.language ===
                            Language.ENGLISH}
                        onclick={() => {
                            currentSettings.language = Language.ENGLISH;
                        }}
                    >
                        <span class="flag">🇺🇸</span>
                        <span>{$t.settings.english}</span>
                    </button>

                    <button
                        class="language-button"
                        class:selected={currentSettings.language ===
                            Language.VIETNAMESE}
                        onclick={() => {
                            currentSettings.language = Language.VIETNAMESE;
                        }}
                    >
                        <span class="flag">🇻🇳</span>
                        <span>{$t.settings.vietnamese}</span>
                    </button>
                </div>
            </section>

            <!-- Advanced Settings (Collapsible) -->
            <section class="settings-section">
                <button
                    class="advanced-toggle"
                    onclick={() => (showAdvanced = !showAdvanced)}
                >
                    <span class="toggle-icon">{showAdvanced ? "▼" : "▶"}</span>
                    <h3>{$t.settings.advanced}</h3>
                </button>

                {#if showAdvanced}
                    <div class="advanced-content">
                        <!-- Backend Port Configuration -->
                        <div class="advanced-subsection">
                            <h4>{$t.settings.backendPort}</h4>

                            <div class="option-list">
                                <label
                                    class="option-row"
                                    class:selected={portMode === "random"}
                                >
                                    <span class="option-label"
                                        >{$t.settings.randomized}</span
                                    >
                                    <input
                                        type="radio"
                                        name="portMode"
                                        value="random"
                                        bind:group={portMode}
                                    />
                                </label>

                                <label
                                    class="option-row"
                                    class:selected={portMode === "custom"}
                                >
                                    <div
                                        class="option-label"
                                        style="display: flex; align-items: center; gap: var(--space-3);"
                                    >
                                        <span>{$t.settings.custom}</span>
                                        <input
                                            type="number"
                                            bind:value={customPort}
                                            disabled={portMode !== "custom"}
                                            min="1024"
                                            max="65535"
                                            class="mac-input"
                                            style="width: 140px; margin-left: auto; text-align: right;"
                                            placeholder="8000"
                                            onfocus={() =>
                                                (portMode = "custom")}
                                            onclick={(e) => e.stopPropagation()}
                                        />
                                    </div>
                                    <input
                                        type="radio"
                                        name="portMode"
                                        value="custom"
                                        bind:group={portMode}
                                    />
                                </label>
                            </div>

                            <p
                                class="help-text"
                                style="margin: var(--space-3) var(--space-3);"
                            >
                                ℹ️ {$t.settings.portDescription}
                                {#if portMode === "random"}
                                    {$t.settings.usingPort}
                                    <strong>{currentPort}</strong>
                                {/if}
                            </p>

                            <button
                                class="btn btn-primary"
                                onclick={handleSavePort}
                            >
                                {$t.settings.savePort}
                            </button>
                        </div>

                        <!-- Database Location -->
                        <div class="advanced-subsection">
                            <h4>{$t.settings.databaseLocation}</h4>

                            <div class="database-path-display">
                                <span class="database-label"
                                    >{$t.settings.currentLocation}</span
                                >
                                <code class="path-text"
                                    >{databasePath || "Loading..."}</code
                                >
                            </div>

                            <div class="database-actions">
                                <button
                                    class="btn btn-primary"
                                    onclick={handleChangeDatabasePath}
                                    disabled={isChangingDatabase}
                                >
                                    {isChangingDatabase
                                        ? $t.settings.changing
                                        : $t.settings.changeLocation}
                                </button>
                                <button
                                    class="btn btn-secondary"
                                    onclick={handleResetDatabasePath}
                                    disabled={isChangingDatabase ||
                                        databasePath === defaultDatabasePath}
                                >
                                    {$t.settings.resetDefault}
                                </button>
                            </div>

                            <p class="help-text">
                                ⚠️ {$t.settings.dbWarning}
                            </p>
                        </div>
                    </div>
                {/if}
            </section>

            {#if errorMessage}
                <div class="error-banner">
                    ❌ {errorMessage}
                </div>
            {/if}

            <!-- Placeholder for Import/Export -->
            <section class="settings-section placeholder">
                <h3>{$t.nav.importExport}</h3>
                <p class="placeholder-text">
                    Import and export functionality will be available soon.
                </p>
            </section>

            <!-- Save Button -->
            <div class="save-section">
                <button class="btn btn-primary" onclick={handleSave}>
                    {$t.settings.saveSettings}
                </button>
            </div>
        </div>
    </div>
</div>

<style>
    .settings-content {
        display: flex;
        flex-direction: column;
        gap: var(--space-6);
        max-width: 800px;
        margin: 0 auto;
    }

    .settings-section {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        padding: var(--space-5);
    }

    .settings-section h3 {
        font-size: var(--font-size-lg);
        font-weight: var(--font-weight-semibold);
        color: var(--text-primary);
        margin: 0 0 var(--space-4) 0;
    }

    .currency-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        gap: var(--space-3);
        margin-bottom: var(--space-4);
    }

    .currency-button {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--space-1);
        padding: var(--space-3);
        background: var(--background);
        border: 2px solid var(--border);
        border-radius: var(--radius-md);
        cursor: pointer;
        transition: all var(--transition-base);
        color: var(--text-primary);
    }

    .currency-button:hover {
        border-color: var(--accent);
        background: rgba(0, 122, 255, 0.05);
    }

    .currency-button.selected {
        border-color: var(--accent);
        background: rgba(0, 122, 255, 0.1);
        color: var(--accent);
    }

    .currency-symbol {
        font-size: var(--font-size-xl);
        font-weight: var(--font-weight-bold);
        color: inherit;
    }

    .currency-name {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .currency-button.selected .currency-name {
        color: var(--accent);
    }

    .custom-currency-input {
        display: flex;
        gap: var(--space-2);
        margin-bottom: var(--space-4);
    }

    /* 
       Note: Inputs are globally styled in forms.css, 
       but we keep the layout styles here.
    */

    /* Helper for custom currency button alignment */
    /* .custom-currency-input button removed as it uses global btn class */

    .current-selection {
        display: flex;
        align-items: center;
        gap: var(--space-2);
        padding: var(--space-3);
        background: var(--background);
        border-radius: var(--radius-md);
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .current-selection strong {
        color: var(--text-primary);
        font-size: var(--font-size-lg);
    }

    .decimals-selector,
    .language-selector {
        display: flex;
        gap: var(--space-3);
    }

    .decimal-button,
    .language-button {
        flex: 1;
        padding: var(--space-3) var(--space-4);
        background: var(--background);
        border: 2px solid var(--border);
        border-radius: var(--radius-md);
        cursor: pointer;
        transition: all var(--transition-base);
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-medium);
        color: var(--text-primary);
    }

    .decimal-button:hover,
    .language-button:hover {
        border-color: var(--accent);
        background: rgba(0, 122, 255, 0.05);
    }

    .decimal-button.selected,
    .language-button.selected {
        border-color: var(--accent);
        background: rgba(0, 122, 255, 0.1);
        color: var(--accent);
    }

    .language-button {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: var(--space-2);
    }

    .flag {
        font-size: var(--font-size-xl);
    }

    .settings-section.placeholder {
        border-style: dashed;
        opacity: 0.6;
    }

    .placeholder-text {
        color: var(--text-secondary);
        font-style: italic;
        margin: 0;
    }

    .save-section {
        display: flex;
        justify-content: flex-end;
        padding-top: var(--space-4);
    }

    /* Database Location Section */
    .database-path-display {
        margin-bottom: var(--space-4);
        padding: var(--space-4);
        background: var(--background);
        border-radius: var(--radius-md);
        border: 1px solid var(--border);
    }

    .database-path-display .database-label {
        display: block;
        font-size: var(--font-size-sm);
        font-weight: var(--font-weight-medium);
        color: var(--text-secondary);
        margin-bottom: var(--space-2);
    }

    .path-text {
        display: block;
        font-family: "SF Mono", "Monaco", "Courier New", monospace;
        font-size: var(--font-size-sm);
        color: var(--text-primary);
        padding: var(--space-2);
        background: rgba(0, 0, 0, 0.02);
        border-radius: var(--radius-sm);
        word-break: break-all;
    }

    .database-actions {
        display: flex;
        gap: var(--space-3);
        margin-bottom: var(--space-3);
    }

    /* Advanced Section */
    .advanced-toggle {
        display: flex;
        align-items: center;
        gap: var(--space-2);
        width: 100%;
        background: none;
        border: none;
        padding: 0;
        cursor: pointer;
        color: var(--text-primary);
    }

    .advanced-toggle h3 {
        margin: 0;
    }

    .toggle-icon {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        transition: transform var(--transition-base);
    }

    .advanced-content {
        margin-top: var(--space-4);
        padding-top: var(--space-4);
        border-top: 1px solid var(--border);
        display: flex;
        flex-direction: column;
        gap: var(--space-5);
    }

    .advanced-subsection h4 {
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-semibold);
        color: var(--text-primary);
        margin: 0 0 var(--space-3) 0;
    }

    /* .port-options removed */

    /* .port-input removed */

    .advanced-subsection {
        padding: var(--space-4);
        background: rgba(0, 0, 0, 0.02);
        border-radius: var(--radius-md);
    }
</style>
