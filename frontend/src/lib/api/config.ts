import { invoke } from '@tauri-apps/api/core';

/**
 * Configuration management API
 * Provides access to the application's INI-based configuration system
 */
export const config = {
    /**
     * Get a configuration value
     * @param section - The INI section name
     * @param key - The configuration key
     * @returns The value as a string, or null if not found
     */
    async get(section: string, key: string): Promise<string | null> {
        return await invoke<string | null>('get_config_value', { section, key });
    },

    /**
     * Set a configuration value
     * @param section - The INI section name
     * @param key - The configuration key
     * @param value - The value to set
     */
    async set(section: string, key: string, value: string): Promise<void> {
        await invoke('set_config_value', { section, key, value });
    },

    /**
     * Remove a configuration value
     * @param section - The INI section name
     * @param key - The configuration key
     */
    async remove(section: string, key: string): Promise<void> {
        await invoke('remove_config_value', { section, key });
    },

    /**
     * Get all configuration sections and values
     * @returns An object with sections as keys and key-value pairs as values
     */
    async getAll(): Promise<Record<string, Record<string, string>>> {
        return await invoke('get_all_config');
    },

    // Convenience methods for common settings

    /**
     * Get the database path
     */
    async getDatabasePath(): Promise<string> {
        return await invoke('get_database_path');
    },

    /**
     * Set the database path
     */
    async setDatabasePath(path: string): Promise<void> {
        await invoke('set_database_path', { path });
    },

    /**
     * Get the currency symbol (default: ¥)
     */
    async getCurrencySymbol(): Promise<string> {
        const symbol = await this.get('app', 'currency_symbol');
        return symbol || '¥';
    },

    /**
     * Set the currency symbol
     */
    async setCurrencySymbol(symbol: string): Promise<void> {
        await this.set('app', 'currency_symbol', symbol);
    },

    /**
     * Get the language (default: en-US)
     */
    async getLanguage(): Promise<string> {
        const language = await this.get('app', 'language');
        return language || 'en-US';
    },

    /**
     * Set the language
     */
    async setLanguage(language: string): Promise<void> {
        await this.set('app', 'language', language);
    },

    /**
     * Get the default database path
     */
    async getDefaultDatabasePath(): Promise<string> {
        return await invoke<string>('get_default_database_path');
    },

    /**
     * Pick a database file using native file picker
     */
    async pickDatabaseFile(): Promise<string | null> {
        return await invoke<string | null>('pick_database_file');
    },

    /**
     * Get the backend port (auto-generated if not set)
     */
    async getBackendPort(): Promise<number> {
        return await invoke<number>('get_backend_port');
    },
};
