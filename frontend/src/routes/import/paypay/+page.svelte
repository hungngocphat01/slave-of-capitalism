<script lang="ts">
    import { onMount } from "svelte";
    import { importWizardStore } from "$lib/stores/import-wizard";
    import { api, waitForBackend } from "$lib/api/client";
    import { importPayPayCsv, compileRules } from "$lib/paypay-importer";
    import { showAlert } from "$lib/utils/dialog";
    import {
        validateCsvSyntax,
        validateRulesSyntax,
        findInvalidCategories,
        extractUniqueWallets,
    } from "$lib/utils/import-helpers";
    import { getCurrentWindow } from "@tauri-apps/api/window";
    import { open } from "@tauri-apps/plugin-dialog";
    import { readTextFile, BaseDirectory } from "@tauri-apps/plugin-fs";

    let loading = $state(false);
    let connecting = $state(true);
    let csvInput: HTMLInputElement; // Keep for fallback/reference if needed, but we use dialog now
    let rulesInput: HTMLInputElement;

    const steps = [
        { number: 1, title: "Select Files", subtitle: "Choose CSV and rules" },
        { number: 2, title: "Map Wallets", subtitle: "Link accounts" },
        { number: 3, title: "Preview", subtitle: "Review transactions" },
        { number: 4, title: "Confirm", subtitle: "Complete import" },
    ];

    // Persistence Keys
    const KEY_WALLET_MAPPING = "paypay_importer_wallet_mapping";
    const KEY_LAST_RULES_DIR = "paypay_importer_last_rules_dir";
    const KEY_LAST_CSV_DIR = "paypay_importer_last_csv_dir";

    async function handleCsvSelect() {
        try {
            const defaultPath =
                localStorage.getItem(KEY_LAST_CSV_DIR) || undefined;
            const file = await open({
                multiple: false,
                directory: false,
                filters: [{ name: "CSV", extensions: ["csv"] }],
                defaultPath,
            });

            if (file) {
                // Save directory for next time (approximation)
                // path is full path, we can't easily get dir in webview without path manipulation
                // which might be OS specific. For now, rely on OS dialog remembering last location
                // or if file path logic allows.
                // Actually, Tauri 2 open returns null or path string (or array).
                const pathStr = file as string;

                const content = await readTextFile(pathStr);
                const validation = validateCsvSyntax(content);

                if (validation.valid) {
                    const wallets = extractUniqueWallets(content);
                    const mapping: Record<string, number> = {};

                    // Load persisted mapping
                    const savedMappingStr =
                        localStorage.getItem(KEY_WALLET_MAPPING);
                    const savedMapping = savedMappingStr
                        ? JSON.parse(savedMappingStr)
                        : {};

                    wallets.forEach((w) => {
                        // Use saved ID if available, otherwise 0
                        mapping[w] = savedMapping[w] || 0;
                    });

                    importWizardStore.update((s) => ({
                        ...s,
                        csvContent: content,
                        walletMapping: mapping,
                        errors: [],
                    }));
                } else {
                    const errorMsg = validation.errors.join("\n");
                    await showAlert(
                        `Invalid CSV File:\n${errorMsg}`,
                        "CSV Validation Error",
                    );
                    importWizardStore.update((s) => ({
                        ...s,
                        csvContent: "",
                        errors: validation.errors,
                    }));
                }
            }
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(err);
            await showAlert(`Failed to read file: ${msg}`, "File Read Error");
        }
    }

    async function handleRulesSelect() {
        try {
            const defaultPath =
                localStorage.getItem(KEY_LAST_RULES_DIR) || undefined;
            const file = await open({
                multiple: false,
                directory: false,
                filters: [{ name: "Rules", extensions: ["txt", "rules"] }],
                defaultPath,
            });

            if (file) {
                const pathStr = file as string;
                // Attempt to save directory (rudimentary)
                // In browser, we can't reliably manipulate paths, but user wants persistence.
                // We'll save the parent dir if we can parse it, or just relying on dialog behavior.

                // Let's store the full path to extract dir later if needed,
                // or just store the file path as "last used".
                // Detailed directory persistence might require backend helper or path lib.
                // For now, let's just store the path to use as defaultPath?
                // open() defaultPath can be a file or dir.
                localStorage.setItem(KEY_LAST_RULES_DIR, pathStr);

                const content = await readTextFile(pathStr);
                // Validate syntax first
                const validation = validateRulesSyntax(content);

                if (validation.valid) {
                    // Try to compile to verify logic
                    try {
                        const ruleLines = content
                            .split("\n")
                            .filter(
                                (l) => l.trim() && !l.trim().startsWith("#"),
                            );
                        compileRules(ruleLines);

                        importWizardStore.update((s) => ({
                            ...s,
                            rulesContent: content,
                            errors: [],
                        }));
                    } catch (compileError) {
                        const msg =
                            compileError instanceof Error
                                ? compileError.message
                                : String(compileError);
                        await showAlert(
                            `Rule compilation failed:\n${msg}`,
                            "Rules Error",
                        );

                        importWizardStore.update((s) => ({
                            ...s,
                            rulesContent: "",
                            errors: [`Rule compilation failed: ${msg}`],
                        }));
                    }
                } else {
                    const errorMsg = validation.errors.join("\n");
                    await showAlert(
                        `Invalid Rules File:\n${errorMsg}`,
                        "Rules Validation Error",
                    );

                    importWizardStore.update((s) => ({
                        ...s,
                        rulesContent: "",
                        errors: validation.errors,
                    }));
                }
            }
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(err);
            await showAlert(
                `Failed to read rules file: ${msg}`,
                "File Read Error",
            );
        }
    }

    function canProceedStep1() {
        return (
            !!$importWizardStore.csvContent && !!$importWizardStore.rulesContent
        );
    }

    async function prepareStep3() {
        if (!$importWizardStore.csvContent || !$importWizardStore.rulesContent)
            return;

        loading = true;
        try {
            const rules = $importWizardStore.rulesContent
                .split("\n")
                .map((l) => l.trim())
                .filter((l) => l && !l.startsWith("#"));

            if ($importWizardStore.walletMapping) {
                // Ensure mapping is complete? No, user can skip.
            }

            // Build category map (Name -> {cat_id, sub_id})
            // We need to handle subcategories recursively if present
            const catMap: Record<
                string,
                { category_id: number; subcategory_id?: number }
            > = {};

            // Recursive helper
            function mapCategory(cat: any) {
                // Map the category itself
                catMap[cat.name] = { category_id: cat.id };

                // Map subcategories if any
                if (cat.subcategories && Array.isArray(cat.subcategories)) {
                    cat.subcategories.forEach((sub: any) => {
                        catMap[sub.name] = {
                            category_id: cat.id,
                            subcategory_id: sub.id,
                        };
                    });
                }
            }

            $importWizardStore.categories.forEach((c) => mapCategory(c));

            const result = await importPayPayCsv(
                $importWizardStore.csvContent,
                rules,
                $importWizardStore.walletMapping,
                catMap,
            );

            importWizardStore.update((s) => ({
                ...s,
                currentStep: 3,
                transformedData: result.rows, // Show rows in UI
                importRequests: result.requests, // Keep requests for submission
                categoryMapping: catMap,
                errors: [],
            }));
        } catch (err) {
            const msg = err instanceof Error ? err.message : "Unknown error";
            await showAlert(
                `Import processing failed:\n${msg}`,
                "Processing Error",
            );

            importWizardStore.update((s) => ({
                ...s,
                errors: [`Import failed: ${msg}`],
            }));
        } finally {
            loading = false;
        }
    }

    let importedCount = $state(0);

    async function nextStep() {
        if ($importWizardStore.currentStep === 1) {
            if (!canProceedStep1()) return;

            if ($importWizardStore.rulesContent) {
                const invalidCats = findInvalidCategories(
                    $importWizardStore.rulesContent,
                    $importWizardStore.categories,
                );
                if (invalidCats.length > 0) {
                    const msg = `Rules contain unknown categories:\n${invalidCats.join("\n")}`;
                    await showAlert(msg, "Invalid Categories");

                    importWizardStore.update((s) => ({
                        ...s,
                        errors: [
                            `Rules contain unknown categories: ${invalidCats.join(", ")}`,
                        ],
                    }));
                    return;
                }
            }

            importWizardStore.update((s) => ({ ...s, currentStep: 2 }));
        } else if ($importWizardStore.currentStep === 2) {
            await prepareStep3();
        } else if ($importWizardStore.currentStep === 3) {
            // PROCEED WITH IMPORT (Formerly Step 3->4 Logic)
            loading = true;
            try {
                const requests = $importWizardStore.importRequests || [];

                if (requests.length === 0) {
                    const msg = "No valid transactions found to import.";
                    await showAlert(msg, "Empty Import");

                    importWizardStore.update((s) => ({
                        ...s,
                        errors: [msg],
                    }));
                    loading = false;
                    return;
                }

                console.log("🚀 Submitting to Backend...");
                const result = await api.transactions.bulkImport(requests);
                console.log("✅ Import Success:", result);

                importedCount = result.imported_count;

                // Move to Success Screen (Step 4)
                importWizardStore.update((s) => ({
                    ...s,
                    currentStep: 4,
                    errors: [], // Clear any errors
                }));
            } catch (e) {
                console.error("Import Error:", e);
                const msg = e instanceof Error ? e.message : String(e);
                importWizardStore.update((s) => ({
                    ...s,
                    errors: [`Import failed: ${msg}`],
                }));
            } finally {
                loading = false;
            }
        }
    }

    function previousStep() {
        if ($importWizardStore.currentStep > 1) {
            importWizardStore.update((s) => ({
                ...s,
                currentStep: s.currentStep - 1,
            }));
        }
    }

    // ... (rest of imports)

    function cancel() {
        getCurrentWindow().close();
    }

    onMount(async () => {
        try {
            // Wait for backend health check
            await waitForBackend();
            connecting = false;
            const [cats, wals] = await Promise.all([
                api.categories.getAll(),
                api.wallets.getAll(),
            ]);
            importWizardStore.update((s) => ({
                ...s,
                categories: cats,
                wallets: wals,
            }));
        } catch (err) {
            console.error(err);
        }
    });

    const stats = $derived({
        total: ($importWizardStore.transformedData || []).length,
        // Check if category string is present (meaning rule matched)
        categorized: ($importWizardStore.transformedData || []).filter(
            (t) => (t as any).category,
        ).length,
        transfers: ($importWizardStore.transformedData || []).filter(
            (t) =>
                t.method === "charge" ||
                t.method === "bank_transfer" ||
                (t as any).wallet_id,
        ).length, // approximate
        uncategorized: ($importWizardStore.transformedData || []).filter(
            (t) =>
                !(t as any).category &&
                t.method !== "charge" &&
                t.method !== "bank_transfer",
        ).length,
    });
</script>

<div class="app-layout">
    <div class="main-content">
        <header class="pane-header">
            <h2 class="screen-title">PayPay Import Wizard</h2>

            <!-- Steps Indicator in Header -->
            <div class="steps-indicator">
                {#each steps as step}
                    <div
                        class="step-item"
                        class:active={$importWizardStore.currentStep ===
                            step.number}
                        class:completed={$importWizardStore.currentStep >
                            step.number}
                    >
                        <div class="step-icon">
                            {#if $importWizardStore.currentStep > step.number}✓{:else}{step.number}{/if}
                        </div>
                        <span class="step-title">{step.title}</span>
                    </div>
                    {#if step.number < steps.length}
                        <div class="step-connector"></div>
                    {/if}
                {/each}
            </div>
        </header>

        <div class="pane-content padded">
            {#if connecting}
                <div
                    class="loading-overlay"
                    style="background: var(--background);"
                >
                    <div class="spinner"></div>
                    <span>Connecting to Backend...</span>
                </div>
            {:else if $importWizardStore.errors.length > 0}
                <div class="error-banner">
                    {#each $importWizardStore.errors as error}
                        <p>{error}</p>
                    {/each}
                </div>
            {/if}

            {#if $importWizardStore.currentStep === 1}
                <div class="step-content-wrapper">
                    <!-- File Inputs no longer used directly, but keeping structure for button -->

                    <div class="file-section">
                        <div class="file-info">
                            <h3>CSV File</h3>
                            <p class="subtitle">
                                Select the CSV file exported from PayPay
                            </p>
                            {#if $importWizardStore.csvContent}
                                <div class="file-success">
                                    <span class="check-icon">✓</span> File loaded
                                    successfully
                                </div>
                            {/if}
                        </div>
                        <button
                            class="btn {$importWizardStore.csvContent
                                ? 'btn-secondary'
                                : 'btn-primary'}"
                            onclick={handleCsvSelect}
                        >
                            {$importWizardStore.csvContent
                                ? "Change File"
                                : "Select CSV"}
                        </button>
                    </div>

                    <div class="file-section">
                        <div class="file-info">
                            <h3>Rules File</h3>
                            <p class="subtitle">
                                Select the rules file for categorization
                            </p>
                            {#if $importWizardStore.rulesContent}
                                <div class="file-success">
                                    <span class="check-icon">✓</span> Rules compiled
                                    successfully
                                </div>
                            {/if}
                        </div>
                        <button
                            class="btn {$importWizardStore.rulesContent
                                ? 'btn-secondary'
                                : 'btn-primary'}"
                            onclick={handleRulesSelect}
                        >
                            {$importWizardStore.rulesContent
                                ? "Change Rules"
                                : "Select Rules"}
                        </button>
                    </div>
                </div>
            {:else if $importWizardStore.currentStep === 2}
                <div class="step-content-wrapper">
                    <h3>Map Wallets</h3>
                    <p class="subtitle">
                        Match CSV wallet names to your accounts context
                    </p>

                    <div class="mapping-list">
                        {#each Object.entries($importWizardStore.walletMapping) as [csvName, walletId]}
                            <div class="mapping-row">
                                <span class="source-name">{csvName}</span>
                                <span class="arrow">→</span>
                                <select
                                    value={walletId}
                                    onchange={(e) => {
                                        const val = parseInt(
                                            e.currentTarget.value,
                                        );
                                        const newMapping = {
                                            ...$importWizardStore.walletMapping,
                                            [csvName]: val,
                                        };

                                        // Update store
                                        importWizardStore.update((s) => ({
                                            ...s,
                                            walletMapping: newMapping,
                                        }));

                                        // Update local storage (merge with existing)
                                        const savedStr =
                                            localStorage.getItem(
                                                KEY_WALLET_MAPPING,
                                            );
                                        const saved = savedStr
                                            ? JSON.parse(savedStr)
                                            : {};
                                        saved[csvName] = val;
                                        localStorage.setItem(
                                            KEY_WALLET_MAPPING,
                                            JSON.stringify(saved),
                                        );
                                    }}
                                    class="wallet-select"
                                >
                                    <option value={0}>Select Wallet...</option>
                                    {#each $importWizardStore.wallets as wallet}
                                        <option value={wallet.id}
                                            >{wallet.name}</option
                                        >
                                    {/each}
                                </select>
                            </div>
                        {/each}
                    </div>
                </div>
            {:else if $importWizardStore.currentStep === 3}
                <div class="step-content-wrapper">
                    <div class="stats-grid">
                        <div class="stat-card">
                            <span class="label">Total</span>
                            <span class="value">{stats.total}</span>
                        </div>
                        <div class="stat-card">
                            <span class="label">Categorized</span>
                            <span class="value success"
                                >{stats.categorized}</span
                            >
                        </div>
                        <div class="stat-card">
                            <span class="label">Uncategorized</span>
                            <span class="value warning"
                                >{stats.uncategorized}</span
                            >
                        </div>
                    </div>

                    <div class="preview-table-container">
                        <table class="preview-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Description</th>
                                    <th>Method</th>
                                    <th class="text-right">Amount</th>
                                    <th>Category</th>
                                </tr>
                            </thead>
                            <tbody>
                                {#each $importWizardStore.transformedData.slice(0, 100) as item}
                                    <tr>
                                        <td>{item.date}</td>
                                        <td>{item.description}</td>
                                        <td>{item.method}</td>
                                        <td
                                            class={item.direction === "inflow"
                                                ? "inflow"
                                                : ""}
                                        >
                                            {item.amount.toLocaleString()}
                                        </td>
                                        <td>
                                            {#if (item as any).category}
                                                {@const mapping =
                                                    $importWizardStore
                                                        .categoryMapping[
                                                        (item as any).category
                                                    ]}
                                                {#if mapping}
                                                    <!-- Resolve real name from ID -->
                                                    {@const realCat =
                                                        $importWizardStore.categories.find(
                                                            (c) =>
                                                                c.id ===
                                                                mapping.category_id,
                                                        )}
                                                    {@const realSub =
                                                        mapping.subcategory_id
                                                            ? $importWizardStore.categories
                                                                  .flatMap(
                                                                      (c) =>
                                                                          c.subcategories ||
                                                                          [],
                                                                  )
                                                                  .find(
                                                                      (s) =>
                                                                          s.id ===
                                                                          mapping.subcategory_id,
                                                                  )
                                                            : null}

                                                    <span
                                                        class="badge badge-category"
                                                    >
                                                        {realCat
                                                            ? realCat.name
                                                            : "Unknown"}
                                                        {#if realSub}
                                                            / {realSub.name}{/if}
                                                    </span>
                                                {:else}
                                                    <!-- Rule matched but no DB mapping found -->
                                                    <span
                                                        class="badge"
                                                        style="background: #ff4444; color: white;"
                                                        title="Category not found in database"
                                                    >
                                                        {(item as any).category}
                                                        (?)
                                                    </span>
                                                {/if}
                                            {:else}
                                                <span class="text-muted">-</span
                                                >
                                            {/if}
                                        </td>
                                    </tr>
                                {/each}
                            </tbody>
                        </table>
                    </div>
                </div>
            {:else if $importWizardStore.currentStep === 4}
                <div class="step-content-wrapper centered-step">
                    <div class="success-icon-large">✓</div>
                    <h3>Import Complete</h3>
                    <p class="subtitle">
                        Your transactions have been successfully imported.
                    </p>

                    <div class="results-card">
                        <div class="result-row">
                            <span>Total CSV Rows</span>
                            <strong>{stats.total}</strong>
                        </div>
                        <div class="result-row">
                            <span>Transactions Created</span>
                            <strong>{importedCount}</strong>
                        </div>
                        <div class="result-row">
                            <span>Skipped/Filtered</span>
                            <strong>{stats.total - importedCount}</strong>
                        </div>
                    </div>

                    <p class="subtitle" style="margin-bottom: 16px;">
                        You can close the window.
                    </p>

                    <button
                        class="btn btn-primary"
                        onclick={() => getCurrentWindow().close()}
                    >
                        Close Window
                    </button>
                </div>
            {/if}

            <!-- DEBUG SECTION -->
            {#if $importWizardStore.transformedData.length > 0 && $importWizardStore.currentStep !== 4}
                <details
                    class="debug-details"
                    style="margin-top: 20px; padding: 10px; background: #eee; border-radius: 4px;"
                >
                    <summary>Debug: Parsed Data Inspection</summary>
                    <div
                        style="margin-top: 10px; font-family: monospace; font-size: 12px; white-space: pre-wrap;"
                    >
                        <p>
                            <strong>First Row Keys:</strong>
                            {JSON.stringify(
                                Object.keys(
                                    $importWizardStore.transformedData[0],
                                ),
                                null,
                                2,
                            )}
                        </p>
                        <p>
                            <strong>First Row Method:</strong>
                            "{$importWizardStore.transformedData[0].method}"
                        </p>
                        <p>
                            <strong>First Row Category (Rule Match):</strong>
                            "{($importWizardStore.transformedData[0] as any)
                                .category || "None"}"
                        </p>
                    </div>
                </details>
            {/if}

            {#if loading}
                <div class="loading-overlay">
                    <div class="spinner"></div>
                    <span>Processing...</span>
                </div>
            {/if}
        </div>

        <div class="modal-footer pane-footer">
            {#if $importWizardStore.currentStep !== 4}
                <button class="btn btn-secondary" onclick={cancel}
                    >Cancel</button
                >
                <div class="footer-actions">
                    <button
                        class="btn btn-secondary"
                        onclick={previousStep}
                        disabled={$importWizardStore.currentStep === 1}
                    >
                        Back
                    </button>
                    <button
                        class="btn btn-primary"
                        onclick={nextStep}
                        disabled={($importWizardStore.currentStep === 1 &&
                            !canProceedStep1()) ||
                            loading}
                    >
                        {#if $importWizardStore.currentStep === 3}
                            Proceed with Import
                        {:else}
                            Next Step
                        {/if}
                    </button>
                </div>
            {/if}
        </div>
    </div>
</div>

<style>
    /* New Styles for Success Screen */
    .centered-step {
        align-items: center;
        text-align: center;
        padding-top: 40px;
    }

    .success-icon-large {
        width: 64px;
        height: 64px;
        background: var(--success);
        color: white;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 32px;
        margin-bottom: 16px;
    }

    .results-card {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        padding: 24px;
        width: 100%;
        max-width: 400px;
        margin: 24px 0;
    }

    .result-row {
        display: flex;
        justify-content: space-between;
        padding: 8px 0;
        border-bottom: 1px solid var(--border);
    }

    .result-row:last-child {
        border-bottom: none;
    }

    /* Layout Overrides to match Pane style */
    .app-layout {
        width: 100vw;
        height: 100vh;
        background: var(--background);
        display: flex;
        flex-direction: column;
    }

    .main-content {
        flex: 1;
        display: flex;
        flex-direction: column;
        overflow: hidden;
    }

    .pane-header {
        justify-content: space-between;
        padding: 0 24px;
    }

    .screen-title {
        font-size: 18px;
    }

    .pane-content {
        flex: 1;
        overflow-y: auto;
        padding: 24px;
        max-width: 900px;
        margin: 0 auto;
        width: 100%;
    }

    .pane-footer {
        padding: 16px 24px;
        border-top: 1px solid var(--border);
        background: var(--surface);
        display: flex;
        justify-content: space-between;
        align-items: center;
    }

    .footer-actions {
        display: flex;
        gap: 12px;
    }

    /* Steps */
    .steps-indicator {
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .step-item {
        display: flex;
        align-items: center;
        gap: 8px;
        color: var(--text-tertiary);
    }

    .step-item.active {
        color: var(--accent);
        font-weight: 500;
    }

    .step-item.completed {
        color: var(--success);
    }

    .step-icon {
        width: 24px;
        height: 24px;
        border-radius: 50%;
        background: var(--surface-elevated);
        border: 2px solid var(--border);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 12px;
        font-weight: bold;
    }

    .step-item.active .step-icon {
        background: var(--accent);
        border-color: var(--accent);
        color: white;
    }

    .step-item.completed .step-icon {
        background: var(--success);
        border-color: var(--success);
        color: white;
    }

    .step-connector {
        width: 24px;
        height: 1px;
        background: var(--border);
    }

    .step-title {
        font-size: 13px;
    }

    /* Content */
    .step-content-wrapper {
        display: flex;
        flex-direction: column;
        gap: 16px;
    }

    .file-section {
        background: var(--surface);
        padding: 24px;
        border-radius: var(--radius-lg);
        border: 1px solid var(--border);
        display: flex;
        align-items: center;
        justify-content: space-between;
    }

    .file-info h3 {
        margin: 0 0 4px 0;
        font-size: 16px;
    }

    .subtitle {
        margin: 0;
        color: var(--text-secondary);
        font-size: 13px;
    }

    .file-success {
        display: flex;
        align-items: center;
        gap: 6px;
        margin-top: 8px;
        color: var(--success);
        font-size: 13px;
        font-weight: 500;
    }

    /* Mapping */
    .mapping-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
    }

    .mapping-row {
        background: var(--surface);
        padding: 12px 16px;
        border-radius: var(--radius-md);
        border: 1px solid var(--border);
        display: flex;
        align-items: center;
        gap: 16px;
    }

    .source-name {
        width: 30%;
        min-width: 150px;
        font-weight: 500;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }

    .wallet-select {
        padding: 6px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--border);
        background: var(--surface-elevated);
        min-width: 200px;
    }

    /* Stats & Preview */
    .stats-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 16px;
        margin-bottom: 24px;
    }

    .stat-card {
        background: var(--surface);
        padding: 16px;
        border-radius: var(--radius-md);
        border: 1px solid var(--border);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
    }

    .stat-card .label {
        font-size: 12px;
        text-transform: uppercase;
        color: var(--text-secondary);
        font-weight: 600;
    }

    .stat-card .value {
        font-size: 24px;
        font-weight: 700;
    }

    .value.success {
        color: var(--success);
    }
    .value.warning {
        color: var(--warning);
    }

    .preview-table-container {
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        overflow: hidden;
    }

    .preview-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 13px;
    }

    .preview-table th {
        background: var(--surface);
        padding: 10px 16px;
        text-align: left;
        font-weight: 600;
        border-bottom: 1px solid var(--border);
        color: var(--text-secondary);
    }

    .preview-table td {
        padding: 10px 16px;
        border-bottom: 1px solid var(--border-light);
    }

    .text-right {
        text-align: right;
    }
    .inflow {
        color: var(--success);
    }

    .loading-overlay {
        position: absolute;
        inset: 0;
        background: rgba(255, 255, 255, 0.8);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 12px;
        z-index: 100;
    }

    @media (max-width: 600px) {
        .steps-indicator .step-title {
            display: none;
        }
    }
</style>
