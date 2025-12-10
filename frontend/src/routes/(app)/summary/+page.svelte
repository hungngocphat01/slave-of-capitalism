<script lang="ts">
    import { onMount } from "svelte";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import type {
        MonthlySummaryResponse,
        CategorySummary,
    } from "$lib/api/types";
    import { showAlert } from "$lib/utils/dialog";

    let currentYear = $state(new Date().getFullYear());
    let currentMonth = $state(new Date().getMonth() + 1);
    let summary = $state<MonthlySummaryResponse | null>(null);
    let loading = $state(true);
    let error = $state<string | null>(null);
    let editingBudget = $state<number | null>(null);
    let editValue = $state("");
    let expandedCategories = $state<Record<number, boolean>>({});

    function toggleCategory(categoryId: number) {
        expandedCategories[categoryId] = !expandedCategories[categoryId];
    }

    function getMonthName(month: number): string {
        const monthKeys = [
            "january",
            "february",
            "march",
            "april",
            "may",
            "june",
            "july",
            "august",
            "september",
            "october",
            "november",
            "december",
        ];
        return $t.months[monthKeys[month - 1] as keyof typeof $t.months];
    }

    async function loadSummary() {
        loading = true;
        error = null;

        try {
            summary = await api.budgets.getMonthlySummary(
                currentYear,
                currentMonth,
            );
        } catch (err) {
            error =
                err instanceof Error ? err.message : "Failed to load summary";
            console.error("Error loading summary:", err);
        } finally {
            loading = false;
        }
    }

    function previousMonth() {
        if (currentMonth === 1) {
            currentMonth = 12;
            currentYear--;
        } else {
            currentMonth--;
        }
        loadSummary();
    }

    function nextMonth() {
        if (currentMonth === 12) {
            currentMonth = 1;
            currentYear++;
        } else {
            currentMonth++;
        }
        loadSummary();
    }

    function startEditBudget(categoryId: number, currentBudget: number) {
        editingBudget = categoryId;
        editValue = currentBudget.toString();
    }

    async function saveBudget(categoryId: number) {
        const amount = parseFloat(editValue);
        if (isNaN(amount) || amount < 0) {
            await showAlert("Please enter a valid amount", "Invalid Input");
            return;
        }

        try {
            // Try to find existing budget
            const budgets = await api.budgets.getAll({
                year: currentYear,
                month: currentMonth,
                category_id: categoryId,
            });

            if (budgets.length > 0) {
                // Update existing
                await api.budgets.update(budgets[0].id, { amount });
            } else {
                // Create new
                await api.budgets.create({
                    category_id: categoryId,
                    year: currentYear,
                    month: currentMonth,
                    amount,
                });
            }

            editingBudget = null;
            loadSummary();
        } catch (err) {
            console.error(err);
        }
    }

    function cancelEdit() {
        editingBudget = null;
        editValue = "";
    }

    function getPercentageColor(percentage: number): string {
        if (percentage === 0) return "var(--text-secondary)";
        if (percentage < 90) return "var(--success)";
        if (percentage <= 110) return "var(--warning)";
        return "var(--error)";
    }

    function formatAmount(amount: number): string {
        return new Intl.NumberFormat("ja-JP", {
            style: "decimal",
            minimumFractionDigits: 0,
            maximumFractionDigits: 1,
        }).format(amount);
    }

    onMount(() => {
        loadSummary();
    });
</script>

<div class="summary-screen">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.summary.title}</h1>

            <div class="month-selector">
                <button
                    class="month-nav-btn"
                    onclick={previousMonth}
                    disabled={loading}
                    aria-label="Previous month"
                >
                    ◀
                </button>

                <div class="month-display">
                    {getMonthName(currentMonth)}
                    {currentYear}
                </div>

                <button
                    class="month-nav-btn"
                    onclick={nextMonth}
                    disabled={loading}
                    aria-label="Next month"
                >
                    ▶
                </button>
            </div>
        </div>
    </header>

    <div class="screen-content">
        {#if loading}
            <div class="loading-state">
                <div class="spinner"></div>
                <p>{$t.common.loading}</p>
            </div>
        {:else if error}
            <div class="error-state">
                <p class="error-message">❌ {error}</p>
                <button class="retry-btn" onclick={loadSummary}> Retry </button>
            </div>
        {:else if summary}
            <div class="summary-table-container">
                <table class="summary-table">
                    <thead>
                        <tr>
                            <th class="category-col">{$t.common.category}</th>
                            <th class="number-col">{$t.summary.totalBudget}</th>
                            <th class="number-col">{$t.summary.totalSpent}</th>
                            <th class="number-col">%</th>
                            {#each summary.period_boundaries as boundary}
                                <th class="period-col">{boundary}</th>
                            {/each}
                        </tr>
                    </thead>
                    <tbody>
                        {#each summary.categories as cat}
                            <tr class="category-row">
                                <td class="category-cell">
                                    <div class="category-info">
                                        {#if cat.subcategories.length > 0}
                                            <button
                                                class="expand-btn"
                                                onclick={() =>
                                                    toggleCategory(
                                                        cat.category_id,
                                                    )}
                                                aria-label={expandedCategories[
                                                    cat.category_id
                                                ]
                                                    ? "Collapse"
                                                    : "Expand"}
                                            >
                                                {expandedCategories[
                                                    cat.category_id
                                                ]
                                                    ? "▼"
                                                    : "▶"}
                                            </button>
                                        {:else}
                                            <span class="expand-spacer"></span>
                                        {/if}
                                        {#if cat.emoji}
                                            <span class="emoji"
                                                >{cat.emoji}</span
                                            >
                                        {/if}
                                        {cat.category_name}
                                    </div>
                                </td>
                                <td class="number-cell">
                                    {#if editingBudget === cat.category_id}
                                        <input
                                            type="number"
                                            bind:value={editValue}
                                            class="budget-input"
                                            onkeydown={(e) => {
                                                if (e.key === "Enter")
                                                    saveBudget(cat.category_id);
                                                if (e.key === "Escape")
                                                    cancelEdit();
                                            }}
                                        />
                                        <div class="edit-actions">
                                            <button
                                                class="save-btn"
                                                onclick={() =>
                                                    saveBudget(cat.category_id)}
                                                >✓</button
                                            >
                                            <button
                                                class="cancel-btn"
                                                onclick={cancelEdit}>✗</button
                                            >
                                        </div>
                                    {:else}
                                        <button
                                            class="budget-value"
                                            onclick={() =>
                                                startEditBudget(
                                                    cat.category_id,
                                                    cat.budget,
                                                )}
                                        >
                                            {formatAmount(cat.budget)}
                                        </button>
                                    {/if}
                                </td>
                                <td class="number-cell"
                                    >{formatAmount(cat.actual)}</td
                                >
                                <td
                                    class="number-cell"
                                    style="color: {getPercentageColor(
                                        cat.percentage,
                                    )}"
                                >
                                    {cat.percentage > 0
                                        ? `${Math.round(cat.percentage)}%`
                                        : "-"}
                                </td>
                                {#each cat.periods as period}
                                    <td class="period-cell">
                                        {period > 0 ? formatAmount(period) : ""}
                                    </td>
                                {/each}
                            </tr>

                            {#if expandedCategories[cat.category_id] && cat.subcategories.length > 0}
                                {#each cat.subcategories as sub}
                                    <tr class="subcategory-row">
                                        <td class="category-cell">
                                            <div class="subcategory-indent">
                                                {sub.subcategory_name}
                                            </div>
                                        </td>
                                        <td class="number-cell sub-text">-</td>
                                        <td class="number-cell sub-value"
                                            >{formatAmount(sub.actual)}</td
                                        >
                                        <td class="number-cell sub-text">-</td>
                                        {#each sub.periods as period}
                                            <td class="period-cell sub-text">
                                                {period > 0
                                                    ? formatAmount(period)
                                                    : ""}
                                            </td>
                                        {/each}
                                    </tr>
                                {/each}
                            {/if}
                        {/each}
                        <tr class="total-row">
                            <td class="category-cell"
                                ><strong>{$t.common.total}</strong></td
                            >
                            <td class="number-cell"
                                ><strong
                                    >{formatAmount(
                                        summary.total_budget,
                                    )}</strong
                                ></td
                            >
                            <td class="number-cell"
                                ><strong
                                    >{formatAmount(
                                        summary.total_actual,
                                    )}</strong
                                ></td
                            >
                            <td
                                class="number-cell"
                                style="color: {getPercentageColor(
                                    summary.total_budget > 0
                                        ? (summary.total_actual /
                                              summary.total_budget) *
                                              100
                                        : 0,
                                )}"
                            >
                                <strong>
                                    {summary.total_budget > 0
                                        ? `${Math.round((summary.total_actual / summary.total_budget) * 100)}%`
                                        : "-"}
                                </strong>
                            </td>
                            <td colspan={summary.period_boundaries.length}></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        {/if}
    </div>
</div>

<style>
    .summary-screen {
        display: flex;
        flex-direction: column;
        height: 100%;
        overflow: hidden;
    }

    /* .screen-header, .header-content, .screen-title moved to global panes.css */

    /* .month-selector, .month-nav-btn, .month-display moved to global panes.css */

    .screen-content {
        flex: 1;
        overflow: auto;
        padding: var(--space-6);
    }

    .loading-state,
    .error-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        height: 100%;
        gap: var(--space-4);
    }

    .spinner {
        width: 48px;
        height: 48px;
        border: 4px solid var(--border);
        border-top-color: var(--accent);
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }

    .error-message {
        color: var(--error);
        font-size: var(--font-size-lg);
        margin: 0;
    }

    .retry-btn {
        padding: var(--space-2) var(--space-4);
        background-color: var(--accent);
        color: white;
        border: none;
        border-radius: var(--radius-md);
        font-size: var(--font-size-base);
        font-weight: var(--font-weight-semibold);
        cursor: pointer;
        transition: all var(--transition-base);
    }

    .retry-btn:hover {
        background-color: #0056b3;
    }

    .summary-table-container {
        background-color: var(--surface-elevated);
        border-radius: var(--radius-lg);
        overflow: hidden;
        box-shadow: var(--shadow-sm);
    }

    .summary-table {
        width: 100%;
        border-collapse: collapse;
    }

    .summary-table thead {
        background-color: var(--surface);
        border-bottom: 2px solid var(--border);
    }

    .summary-table th {
        padding: var(--space-3) var(--space-4);
        text-align: left;
        font-size: var(--font-size-sm);
        font-weight: var(--font-weight-semibold);
        color: var(--text-secondary);
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    .summary-table td {
        padding: var(--space-3) var(--space-4);
        border-bottom: 1px solid var(--border);
    }

    .summary-table tbody tr:hover {
        background-color: var(--surface);
    }

    .category-col {
        width: 200px;
    }

    .number-col {
        width: 100px;
        text-align: right;
    }

    .period-col {
        width: 80px;
        text-align: right;
    }

    .summary-table th.number-col,
    .summary-table th.period-col {
        text-align: right;
    }

    .category-cell {
        display: flex;
        align-items: center;
        gap: var(--space-2);
        font-weight: var(--font-weight-medium);
    }

    .emoji {
        font-size: var(--font-size-lg);
    }

    .number-cell {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }

    .period-cell {
        text-align: right;
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
        font-variant-numeric: tabular-nums;
    }

    .budget-value {
        background: none;
        border: none;
        color: var(--text-primary);
        cursor: pointer;
        padding: 2px 4px;
        border-radius: var(--radius-sm);
        transition: background-color var(--transition-base);
        font-size: var(--font-size-base);
        font-variant-numeric: tabular-nums;
    }

    .budget-value:hover {
        background-color: var(--border-light);
    }

    .budget-input {
        width: 80px;
        padding: 2px 4px;
        border: 1px solid var(--accent);
        border-radius: var(--radius-sm);
        font-size: var(--font-size-base);
        text-align: right;
    }

    .edit-actions {
        display: inline-flex;
        gap: var(--space-1);
        margin-left: var(--space-2);
    }

    .save-btn,
    .cancel-btn {
        padding: 2px 6px;
        border: none;
        border-radius: var(--radius-sm);
        cursor: pointer;
        font-size: var(--font-size-sm);
        transition: all var(--transition-base);
    }

    .save-btn {
        background-color: var(--success);
        color: white;
    }

    .save-btn:hover {
        background-color: #28a745;
    }

    .cancel-btn {
        background-color: var(--error);
        color: white;
    }

    .cancel-btn:hover {
        background-color: #c82333;
    }

    .total-row {
        background-color: var(--surface);
        font-weight: var(--font-weight-bold);
    }

    .total-row td {
        border-top: 2px solid var(--border);
        border-bottom: none;
    }

    /* Subcategory Styles */
    .category-info {
        display: flex;
        align-items: center;
        gap: var(--space-2);
    }

    .expand-btn {
        background: none;
        border: none;
        cursor: pointer;
        padding: 0;
        width: 16px;
        height: 16px;
        font-size: 10px;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--text-secondary);
        transition: color var(--transition-base);
    }

    .expand-btn:hover {
        color: var(--text-primary);
    }

    .expand-spacer {
        width: 16px;
    }

    .subcategory-row {
        background-color: var(
            --surface
        ); /* Slightly different color (grey vs white) */
    }

    .subcategory-indent {
        padding-left: 40px; /* Indentation */
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .sub-text {
        font-size: var(--font-size-sm);
        color: var(--text-secondary);
    }

    .sub-value {
        font-size: var(--font-size-sm);
        color: var(--text-primary);
        font-weight: var(--font-weight-medium);
    }
</style>
