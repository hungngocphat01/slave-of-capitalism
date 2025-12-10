import { writable } from 'svelte/store';
import type { CategoryWithSubcategories, Wallet } from '$lib/api/types';
import type { ApiRequest, TransformedRow, CategoryMapEntry } from 'paypay-importer';

export interface ImportWizardState {
    currentStep: number;
    csvContent: string | null;
    rulesContent: string | null;
    walletMapping: Record<string, number>;
    categoryMapping: Record<string, CategoryMapEntry>;
    transformedData: TransformedRow[]; // For UI preview
    importRequests: ApiRequest[];      // For submission
    errors: string[];
    categories: CategoryWithSubcategories[]; // Note: this likely contains subcategories via children or similar structure if API returns it
    wallets: Wallet[];
}

const initialState: ImportWizardState = {
    currentStep: 1,
    csvContent: null,
    rulesContent: null,
    walletMapping: {},
    categoryMapping: {},
    transformedData: [],
    importRequests: [],
    errors: [],
    categories: [],
    wallets: [],
};

export const importWizardStore = writable<ImportWizardState>(initialState);

export function resetWizard() {
    importWizardStore.set(initialState);
}
