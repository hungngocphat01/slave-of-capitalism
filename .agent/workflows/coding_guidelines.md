---
description: Coding guidelines and best practices for this project
---

# Coding Guidelines

## UI/UX Rules

1.  **NO `window.alert()`**:
    *   **Rule**: Do NOT use `window.alert()`, `window.confirm()`, or `window.prompt()` for user interaction or error handling.
    *   **Reason**: Native alerts are blocking, can close immediately due to event propagation issues (especially with keyboard events), and provide a poor user experience.
    *   **Alternative**: Use inline validation errors (e.g., red borders, error messages text), custom modal components (e.g., `ConfirmDialog.svelte`, `Modal.svelte`), or non-blocking toast notifications.
    *   **Exception**: `console.error` is acceptable for logging failures that don't need immediate user rectification or when a UI component isn't available yet.

2.  **Event Handling**:
    *   **Rule**: When handling keyboard events (like `Enter` to save), always use `event.preventDefault()` and `event.stopPropagation()` to prevent unwanted side effects (like form submission or bubbling to parent handlers).

## Frontend Architecture

*   **Svelte**: Use Svelte 5 runes (`$state`, `$derived`, `$props`) for reactivity.
*   **Styling**: Use standard CSS in `<style>` blocks. Avoid Tailwind unless explicitly requested.

## general

*   **Accessibility**: Ensure all interactive elements have labels or aria-labels.

## Business Logic Reference

For understanding the application's business logic, see the modular documentation:

*   **[README.md](./README.md)** - Documentation index and navigation
*   **[installment_feature.md](./installment_feature.md)** - Credit card installment plans
*   **[BUSINESS_LOGIC_SPECS.md](./BUSINESS_LOGIC_SPECS.md)** - Legacy (being deprecated)

When implementing new features, document them in separate focused files following the pattern in `installment_feature.md`.
