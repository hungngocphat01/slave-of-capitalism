<script lang="ts">
    import { onMount } from "svelte";
    import { api } from "$lib/api/client";
    import { t } from "$lib/i18n";
    import { fade, fly } from "svelte/transition";
    import { InformationCircle } from "svelte-heros-v2";
    import Modal from "$lib/components/modals/Modal.svelte";
    import type {
        CategoryWithSubcategories,
        Category,
        Subcategory,
    } from "$lib/api/types";
    import { showAlert } from "$lib/utils/dialog";

    // State
    let categories = $state<CategoryWithSubcategories[]>([]);
    let selectedCategory = $state<CategoryWithSubcategories | null>(null);
    let loading = $state(true);
    let error = $state<string | null>(null);

    // Edit states
    let editingCategory = $state(false);
    let categoryName = $state("");
    let categoryEmoji = $state("");
    let categoryColor = $state("");

    // Apple System Colors (Light Mode) for selection
    const PALETTE_COLORS = [
        "#007AFF", // Blue
        "#34C759", // Green
        "#FFCC00", // Yellow
        "#FF9500", // Orange
        "#AF52DE", // Purple
        "#5AC8FA", // Teal
        "#5856D6", // Indigo
        "#FF2D55", // Pink
        "#FF3B30", // Red
        "#8E8E93", // Gray
    ];

    // Deletion modal state
    let showDeleteModal = $state(false);
    let deleteTarget = $state<{
        type: "category" | "subcategory";
        id: number;
        name: string;
    } | null>(null);
    let replacementCategoryId = $state<number | null>(null);
    let replacementSubcategoryId = $state<number | null>(null);
    let deleteError = $state<string | null>(null);

    // New category/subcategory modal
    let showNewCategoryModal = $state(false);
    let showNewSubcategoryModal = $state(false);
    let editingSubcategory = $state<Subcategory | null>(null);
    let newName = $state("");

    let newEmoji = $state("");
    let newColor = $state(PALETTE_COLORS[0]);

    // Load categories
    async function loadCategories() {
        try {
            loading = true;
            error = null;
            categories = await api.categories.getAll();

            // If a category was selected, refresh it
            if (selectedCategory) {
                const updated = categories.find(
                    (c) => c.id === selectedCategory!.id,
                );
                selectedCategory = updated || null;
            }
        } catch (e) {
            error =
                e instanceof Error ? e.message : "Failed to load categories";
            console.error("Failed to load categories:", e);
        } finally {
            loading = false;
        }
    }

    onMount(() => {
        loadCategories();
    });

    // Select category
    function selectCategory(category: CategoryWithSubcategories) {
        selectedCategory = category;
        editingCategory = false;
        categoryName = category.name;
        categoryEmoji = category.emoji || "";
        categoryColor = category.color || PALETTE_COLORS[0];
    }

    // Start editing category
    function startEditCategory() {
        if (!selectedCategory) return;
        editingCategory = true;
    }

    // Save category changes
    async function saveCategory() {
        if (!selectedCategory || !categoryName.trim()) return;

        try {
            await api.categories.update(selectedCategory.id, {
                name: categoryName.trim(),
                emoji: categoryEmoji.trim() || undefined,
                color: categoryColor,
            });
            editingCategory = false;
            await loadCategories();
        } catch (e) {
            console.error("Failed to update category:", e);
        }
    }

    // Cancel editing
    function cancelEdit() {
        if (selectedCategory) {
            categoryName = selectedCategory.name;
            categoryEmoji = selectedCategory.emoji || "";
            categoryColor = selectedCategory.color || PALETTE_COLORS[0];
        }
        editingCategory = false;
    }

    // Delete category
    function confirmDeleteCategory(category: CategoryWithSubcategories) {
        deleteTarget = {
            type: "category",
            id: category.id,
            name: category.name,
        };
        replacementCategoryId = null;
        replacementSubcategoryId = null;
        deleteError = null;
        showDeleteModal = true;
    }

    // Delete subcategory
    function confirmDeleteSubcategory(subcategory: Subcategory) {
        deleteTarget = {
            type: "subcategory",
            id: subcategory.id,
            name: subcategory.name,
        };
        replacementCategoryId = null;
        replacementSubcategoryId = null;
        deleteError = null;
        showDeleteModal = true;
    }

    // Execute deletion
    async function executeDelete() {
        if (!deleteTarget) return;

        try {
            deleteError = null;

            if (deleteTarget.type === "category") {
                await api.categories.delete(
                    deleteTarget.id,
                    replacementCategoryId || undefined,
                    replacementSubcategoryId || undefined,
                );
                if (selectedCategory?.id === deleteTarget.id) {
                    selectedCategory = null;
                }
            } else {
                await api.subcategories.delete(
                    deleteTarget.id,
                    replacementCategoryId || undefined,
                    replacementSubcategoryId || undefined,
                );
            }

            showDeleteModal = false;
            deleteTarget = null;
            await loadCategories();
        } catch (e) {
            // Using a generic error message or assuming ApiError is handled via the response wrapper typically,
            // but here we check for message property manually if we don't import ApiError explicitly or if types differ.
            // Simplified error handling:
            deleteError = e instanceof Error ? e.message : "Failed to delete";
        }
    }

    // Create new category
    async function createCategory() {
        if (!newName.trim()) return;

        try {
            await api.categories.create({
                name: newName.trim(),
                emoji: newEmoji.trim() || undefined,
                color: newColor,
            });
            showNewCategoryModal = false;
            newName = "";
            newEmoji = "";
            newColor = PALETTE_COLORS[0];
            await loadCategories();
        } catch (e) {
            console.error("Failed to create category:", e);
        }
    }

    // Save subcategory (create or update)
    async function saveSubcategory() {
        if (!selectedCategory || !newName.trim()) return;

        try {
            if (editingSubcategory) {
                await api.subcategories.update(editingSubcategory.id, {
                    name: newName.trim(),
                });
            } else {
                await api.subcategories.create(selectedCategory.id, {
                    name: newName.trim(),
                });
            }
            showNewSubcategoryModal = false;
            editingSubcategory = null;
            newName = "";
            await loadCategories();
        } catch (e) {
            console.error("Failed to save subcategory:", e);
        }
    }

    function openNewSubcategoryModal() {
        editingSubcategory = null;
        newName = "";
        showNewSubcategoryModal = true;
    }

    function openEditSubcategoryModal(subcategory: Subcategory) {
        editingSubcategory = subcategory;
        newName = subcategory.name;
        showNewSubcategoryModal = true;
    }

    // Get available replacement categories (excluding the one being deleted and system categories)
    $effect(() => {
        if (deleteTarget?.type === "category") {
            // Filter out the category being deleted
            const available = categories.filter(
                (c) => c.id !== deleteTarget!.id,
            );
            if (available.length > 0 && !replacementCategoryId) {
                replacementCategoryId = available[0].id;
            }
        }
    });

    // Get available replacement subcategories
    let replacementSubcategories = $derived(() => {
        if (!replacementCategoryId) return [];
        const cat = categories.find((c) => c.id === replacementCategoryId);
        return cat?.subcategories || [];
    });
</script>

<div class="mac-layout">
    <header class="screen-header">
        <div class="header-content">
            <h1 class="screen-title">{$t.categories.title}</h1>
        </div>
    </header>

    {#if loading}
        <div class="loading-state">
            <div class="spinner"></div>
            <p>Loading...</p>
        </div>
    {:else if error}
        <div class="error-state">
            <p>{error}</p>
        </div>
    {:else}
        <div class="split-view">
            <!-- Left Pane: Categories Source List -->
            <div class="sidebar-pane">
                <div class="pane-header">
                    <h2>{$t.categories.title}</h2>
                    <button
                        class="btn-icon"
                        onclick={() => {
                            showNewCategoryModal = true;
                        }}
                        title={$t.categories.addCategory}
                    >
                        <span class="icon-plus">+</span>
                    </button>
                </div>
                <div class="pane-content">
                    <div class="list-group">
                        {#each categories as category}
                            <div
                                class="list-row {selectedCategory?.id ===
                                category.id
                                    ? 'selected'
                                    : ''}"
                                onclick={() => selectCategory(category)}
                                tabindex="0"
                                role="button"
                                onkeydown={(e) =>
                                    e.key === "Enter" &&
                                    selectCategory(category)}
                            >
                                <div class="row-content">
                                    <span class="emoji"
                                        >{category.emoji || "📁"}</span
                                    >
                                    <span class="name">{category.name}</span>
                                </div>
                            </div>
                        {/each}
                    </div>
                </div>
            </div>

            <!-- Middle Pane: Category Settings -->
            <div class="detail-pane">
                {#if selectedCategory}
                    <div class="pane-header">
                        <h2>{$t.categories.details}</h2>
                        <div class="header-actions">
                            {#if editingCategory}
                                <button class="btn-text" onclick={cancelEdit}
                                    >{$t.common.cancel}</button
                                >
                                <button
                                    class="btn-text primary"
                                    onclick={saveCategory}
                                    >{$t.common.save}</button
                                >
                            {:else}
                                <button
                                    class="btn-text primary action-hidden"
                                    onclick={startEditCategory}
                                    >{$t.common.edit}</button
                                >
                                {#if !selectedCategory.is_system}
                                    <button
                                        class="btn-text danger action-hidden"
                                        onclick={() =>
                                            confirmDeleteCategory(
                                                selectedCategory!,
                                            )}
                                    >
                                        {$t.common.delete}
                                    </button>
                                {/if}
                            {/if}
                        </div>
                    </div>

                    <div class="pane-content padded">
                        {#if selectedCategory.is_system}
                            <div class="system-banner">
                                <span class="icon"
                                    ><InformationCircle size="20" /></span
                                >
                                <p>{$t.categories.systemCategory}</p>
                            </div>
                        {/if}

                        <div class="mac-form">
                            <div class="form-row">
                                <label for="category-name"
                                    >{$t.categories.name}</label
                                >
                                <input
                                    id="category-name"
                                    type="text"
                                    bind:value={categoryName}
                                    disabled={!editingCategory}
                                    class="mac-input"
                                />
                            </div>

                            <div class="form-row">
                                <label for="category-emoji"
                                    >{$t.categories.emoji}</label
                                >
                                <input
                                    id="category-emoji"
                                    type="text"
                                    bind:value={categoryEmoji}
                                    disabled={!editingCategory}
                                    class="mac-input short"
                                    maxlength="10"
                                />
                            </div>

                            <div class="form-row">
                                <span class="label-text">Color</span>
                                <div class="color-options">
                                    {#if editingCategory}
                                        <div class="palette-grid">
                                            {#each PALETTE_COLORS as color}
                                                <button
                                                    class="color-swatch {categoryColor ===
                                                    color
                                                        ? 'selected'
                                                        : ''}"
                                                    style="background-color: {color};"
                                                    onclick={() =>
                                                        (categoryColor = color)}
                                                    aria-label="Select color {color}"
                                                ></button>
                                            {/each}
                                        </div>
                                    {:else}
                                        <div
                                            class="color-swatch display-only"
                                            style="background-color: {categoryColor};"
                                        ></div>
                                    {/if}
                                </div>
                            </div>
                        </div>
                    </div>
                {:else}
                    <div class="empty-selection">
                        <p>{$t.categories.selectToView}</p>
                    </div>
                {/if}
            </div>

            <!-- Right Pane: Subcategories -->
            <div class="detail-pane alt-bg">
                {#if selectedCategory}
                    <div class="pane-header">
                        <h2>{$t.categories.subcategories}</h2>
                        <button
                            class="btn-icon"
                            onclick={openNewSubcategoryModal}
                            title={$t.categories.addSubcategory}
                        >
                            <span class="icon-plus">+</span>
                        </button>
                    </div>
                    <div class="pane-content">
                        <div class="list-group inset">
                            {#each selectedCategory.subcategories as subcategory}
                                <div class="list-row interactable">
                                    <div class="row-content">
                                        <span class="name"
                                            >{subcategory.name}</span
                                        >
                                    </div>

                                    <div class="row-actions">
                                        <!-- Edit: Always available (appears on hover) -->
                                        <button
                                            class="action-btn edit"
                                            onclick={(e) => {
                                                e.stopPropagation();
                                                openEditSubcategoryModal(
                                                    subcategory,
                                                );
                                            }}
                                        >
                                            Edit
                                        </button>

                                        <!-- Delete: Only if subcategory is NOT system -->
                                        {#if !subcategory.is_system}
                                            <button
                                                class="action-btn delete"
                                                onclick={(e) => {
                                                    e.stopPropagation();
                                                    confirmDeleteSubcategory(
                                                        subcategory,
                                                    );
                                                }}
                                            >
                                                Delete
                                            </button>
                                        {/if}
                                    </div>
                                </div>
                            {/each}
                            {#if selectedCategory.subcategories.length === 0}
                                <div class="empty-list-message">
                                    {$t.categories.noSubcategories}
                                </div>
                            {/if}
                        </div>
                    </div>
                {:else}
                    <div class="empty-selection">
                        <p>{$t.categories.selectToViewSub}</p>
                    </div>
                {/if}
            </div>
        </div>
    {/if}
</div>

<!-- Delete Confirmation Modal -->
{#if showDeleteModal && deleteTarget}
    <Modal
        title="Delete {deleteTarget.type === 'category'
            ? 'Category'
            : 'Subcategory'}"
        onClose={() => {
            showDeleteModal = false;
        }}
    >
        <div class="modal-content">
            <p style="margin-bottom: var(--space-4);">
                Are you sure you want to delete "{deleteTarget.name}"? This
                action cannot be undone.
            </p>

            <div class="form-row vertical">
                <label for="replacement-category"
                    >Replacement Category (required if transactions exist)</label
                >
                <select
                    id="replacement-category"
                    bind:value={replacementCategoryId}
                    class="mac-select"
                >
                    <option value={null}>-- Select replacement --</option>
                    {#each categories.filter((c) => c.id !== deleteTarget?.id) as cat}
                        <option value={cat.id}
                            >{cat.emoji || "📁"} {cat.name}</option
                        >
                    {/each}
                </select>
            </div>

            {#if replacementCategoryId}
                <div class="form-row vertical">
                    <label for="replacement-subcategory"
                        >Replacement Subcategory</label
                    >
                    <select
                        id="replacement-subcategory"
                        bind:value={replacementSubcategoryId}
                        class="mac-select"
                    >
                        <option value={null}>-- None --</option>
                        {#each replacementSubcategories() as sub}
                            <option value={sub.id}>{sub.name}</option>
                        {/each}
                    </select>
                </div>
            {/if}

            {#if deleteError}
                <div class="error-banner">{deleteError}</div>
            {/if}
        </div>

        {#snippet footer()}
            <button
                class="btn mac-btn secondary"
                onclick={() => {
                    showDeleteModal = false;
                }}>Cancel</button
            >
            <button class="btn mac-btn destructive" onclick={executeDelete}
                >Delete</button
            >
        {/snippet}
    </Modal>
{/if}

<!-- New/Edit Modal -->
{#if showNewCategoryModal || showNewSubcategoryModal}
    <Modal
        title={showNewCategoryModal
            ? "New Category"
            : editingSubcategory
              ? "Edit Subcategory"
              : "New Subcategory"}
        onClose={() => {
            showNewCategoryModal = false;
            showNewSubcategoryModal = false;
        }}
    >
        <div class="modal-content">
            <div class="form-row vertical">
                <label for="modal-name">Name</label>
                <input
                    id="modal-name"
                    type="text"
                    bind:value={newName}
                    class="mac-input"
                    placeholder="Name"
                />
            </div>

            {#if showNewCategoryModal}
                <div class="form-row vertical">
                    <label for="modal-emoji">Emoji</label>
                    <input
                        id="modal-emoji"
                        type="text"
                        bind:value={newEmoji}
                        class="mac-input short"
                        placeholder="🍔"
                        maxlength="10"
                    />
                </div>

                <div class="form-row vertical">
                    <label>Color</label>
                    <div class="palette-grid">
                        {#each PALETTE_COLORS as color}
                            <button
                                class="color-swatch {newColor === color
                                    ? 'selected'
                                    : ''}"
                                style="background-color: {color};"
                                onclick={() => (newColor = color)}
                                type="button"
                            ></button>
                        {/each}
                    </div>
                </div>
            {/if}
        </div>

        {#snippet footer()}
            <button
                class="btn mac-btn secondary"
                onclick={() => {
                    showNewCategoryModal = false;
                    showNewSubcategoryModal = false;
                    newName = "";
                    newEmoji = "";
                    newColor = PALETTE_COLORS[0];
                    editingSubcategory = null;
                }}>Cancel</button
            >
            <button
                class="btn mac-btn primary"
                onclick={showNewCategoryModal
                    ? createCategory
                    : saveSubcategory}
                disabled={!newName.trim()}>Save</button
            >
        {/snippet}
    </Modal>
{/if}

<style>
    /* Specific overrides */
    .mac-form .form-row {
        align-items: center;
        min-height: 40px;
    }

    .mac-form .form-row label,
    .mac-form .form-row .label-text {
        width: 60px; /* Reduced width to minimize gap */
        flex-shrink: 0;
        font-size: 13px;
        color: var(--text-secondary);
    }

    /* Color Picker Styles */
    .palette-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
    }

    .color-options {
        display: flex;
        align-items: center;
    }

    .color-swatch {
        width: 24px;
        height: 24px;
        border-radius: 50%;
        border: 2px solid transparent;
        cursor: pointer;
        transition:
            transform 0.1s,
            border-color 0.2s;
        padding: 0;
    }

    .color-swatch.display-only {
        cursor: default;
        border: 1px solid rgba(0, 0, 0, 0.1);
    }

    .color-swatch:not(.display-only):hover {
        transform: scale(1.1);
    }

    .color-swatch.selected {
        border-color: var(--text-primary);
        box-shadow:
            0 0 0 1px var(--bg-primary),
            0 0 0 2px var(--text-primary);
    }

    .mac-input.short {
        flex: 0;
        width: 60px;
        text-align: center;
    }

    /* Icon in list - may not be global */
    .icon-plus {
        font-size: 18px;
        line-height: 1;
        font-weight: 300;
    }
</style>
