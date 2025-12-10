<script lang="ts">
  // Global Root Layout
  // Handles global CSS and API initialization only
  // Logic specific to the main app (sidebar, nav) is now in src/routes/(app)/+layout.svelte

  import "../app.css";
  import "../styles/typography.css";
  import "../styles/buttons.css";
  import "../styles/forms.css";
  import "../styles/table.css";
  import "../styles/modal.css";
  import "../styles/panes.css";

  import { onMount } from "svelte";
  import { initializeApiClient, waitForBackend } from "$lib/api/client";
  import { showAlert } from "$lib/utils/dialog";

  let loading = true;
  let statusMessage = "Starting backend...";

  // Initialize API client globally with backend port from Tauri
  onMount(async () => {
    try {
      await initializeApiClient();
      await waitForBackend();
      loading = false;
    } catch (e) {
      console.error("Failed to start backend:", e);
      statusMessage = "Failed to start backend.";

      const errorMsg = e instanceof Error ? e.message : String(e);
      await showAlert(
        `Failed to start backend service.\n\nError: ${errorMsg}\n\nPlease simply try restarting the application.`,
        "Startup Error",
      );
    }
  });
</script>

{#if loading}
  <div class="startup-loading">
    <div class="spinner"></div>
    <p>{statusMessage}</p>
  </div>
{:else}
  <!-- Global slot for all routes (app and standalone windows) -->
  <slot />
{/if}

<style>
  .startup-loading {
    height: 100vh;
    width: 100vw;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1.5rem;
    background-color: var(--bg-primary, #ffffff);
    color: var(--text-primary, #333333);
    font-family: var(--font-body, system-ui, sans-serif);
    -webkit-user-select: none;
    user-select: none;
    cursor: default;
  }

  .spinner {
    width: 40px;
    height: 40px;
    border: 3px solid rgba(0, 0, 0, 0.1);
    border-radius: 50%;
    border-top-color: var(--primary, #3b82f6);
    animation: spin 1s ease-in-out infinite;
  }

  @media (prefers-color-scheme: dark) {
    .spinner {
      border-color: rgba(255, 255, 255, 0.1);
      border-top-color: var(--primary, #60a5fa);
    }
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  p {
    font-size: 0.9rem;
    color: var(--text-secondary, #666666);
    font-weight: 500;
  }
</style>
