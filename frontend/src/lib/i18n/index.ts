import { derived } from 'svelte/store';
import { settings } from '$lib/stores/settings';
import { translations, type Language } from './translations';

// Create a derived store that provides the current translations
export const t = derived(settings, ($settings) => {
    const lang = $settings.language;
    return translations[lang];
});

// Helper function to format currency
export function formatCurrency(amount: number, settingsValue: { currency: string; decimals: number }): string {
    const formatted = amount.toLocaleString('en-US', {
        minimumFractionDigits: settingsValue.decimals,
        maximumFractionDigits: settingsValue.decimals
    });
    return `${settingsValue.currency}${formatted}`;
}

// Helper to get translation by path (for dynamic keys)
export function getTranslation(lang: Language, path: string): string {
    const keys = path.split('.');
    let value: any = translations[lang];

    for (const key of keys) {
        value = value?.[key];
    }

    return typeof value === 'string' ? value : path;
}
