import { writable } from 'svelte/store';

export enum Language {
    ENGLISH = 'en',
    VIETNAMESE = 'vi'
}

export interface Settings {
    currency: string;
    decimals: number;
    language: Language;
    databasePath: string;
}

const DEFAULT_SETTINGS: Settings = {
    currency: '¥',
    decimals: 0,
    language: Language.ENGLISH,
    databasePath: '' // Will be loaded from Tauri config
};

// Load from localStorage or use defaults
function loadSettings(): Settings {
    if (typeof window === 'undefined') return DEFAULT_SETTINGS;

    const stored = localStorage.getItem('expense-manager-settings');
    if (stored) {
        try {
            return { ...DEFAULT_SETTINGS, ...JSON.parse(stored) };
        } catch {
            return DEFAULT_SETTINGS;
        }
    }
    return DEFAULT_SETTINGS;
}

function createSettingsStore() {
    const { subscribe, set, update } = writable<Settings>(loadSettings());

    return {
        subscribe,
        set: (value: Settings) => {
            if (typeof window !== 'undefined') {
                localStorage.setItem('expense-manager-settings', JSON.stringify(value));
            }
            set(value);
        },
        update: (fn: (value: Settings) => Settings) => {
            update((current) => {
                const newValue = fn(current);
                if (typeof window !== 'undefined') {
                    localStorage.setItem('expense-manager-settings', JSON.stringify(newValue));
                }
                return newValue;
            });
        },
        reset: () => {
            if (typeof window !== 'undefined') {
                localStorage.removeItem('expense-manager-settings');
            }
            set(DEFAULT_SETTINGS);
        }
    };
}

export const settings = createSettingsStore();
