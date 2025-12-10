import { message, ask } from '@tauri-apps/plugin-dialog';

/**
 * Show a native alert dialog using Tauri's dialog API
 * @param messageText - The message to display
 * @param title - Optional title for the dialog
 */
export async function showAlert(messageText: string, title?: string): Promise<void> {
    await message(messageText, title || 'Alert');
}

/**
 * Show a native confirmation dialog using Tauri's dialog API
 * @param messageText - The confirmation message to display
 * @param title - Optional title for the dialog
 * @returns Promise<boolean> - true if user clicked OK/Yes, false if user clicked Cancel/No
 */
export async function showConfirm(messageText: string, title?: string): Promise<boolean> {
    return await ask(messageText, title || 'Confirm');
}
