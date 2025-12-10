import type {
    Transaction,
    Wallet,
    Category,
    CategoryWithSubcategories,
    Subcategory,
    LinkedEntry,
    PopulatedTransaction,
    CreateTransactionRequest,
    UpdateTransactionRequest,
    CreateWalletTransferRequest,
    MarkAsSplitRequest,
    MarkAsLoanRequest,
    MarkAsDebtRequest,
    LinkToEntryRequest,
    MonthlyExpenseResponse,
    Classification,
    Budget,
    BudgetWithCategory,
    CreateBudgetRequest,
    UpdateBudgetRequest,
    MonthlySummaryResponse,
    TransactionMergeRequest,
} from './types';
import { invoke } from '@tauri-apps/api/core';
import { showAlert } from '$lib/utils/dialog';

// Dynamic API base URL - will be initialized from Tauri
let API_BASE_URL = 'http://localhost:8000/api'; // fallback for dev mode

/**
 * Initialize the API client with the backend port from Tauri.
 * Must be called before making any API requests.
 */
export async function initializeApiClient(): Promise<void> {
    try {
        const port = await invoke<number>('get_backend_port');
        API_BASE_URL = `http://localhost:${port}/api`;
    } catch (e) {
        // Show error dialog if port fetch fails in production
        await showAlert(
            `Failed to get backend port: ${e}\n\nUsing default port 8000.`,
            'Backend Configuration Error'
        );
    }
}

/**
 * Wait for the backend to become available by polling the health endpoint.
 * @param maxRetries Maximum number of retries (default: 30)
 * @param delayMs Delay between retries in ms (default: 1000)
 */
export async function waitForBackend(maxRetries = 30, delayMs = 500): Promise<void> {
    for (let i = 0; i < maxRetries; i++) {
        try {
            await fetchApi('/health');
            return;
        } catch (e) {
            // Ignore errors and wait
            await new Promise(resolve => setTimeout(resolve, delayMs));
        }
    }
    throw new Error('Backend failed to start. Please check the logs.');
}

class ApiError extends Error {
    constructor(public status: number, message: string) {
        super(message);
        this.name = 'ApiError';
    }
}

async function fetchApi<T>(
    endpoint: string,
    options?: RequestInit
): Promise<T> {
    const url = `${API_BASE_URL}${endpoint}`;

    try {
        const response = await fetch(url, {
            ...options,
            cache: 'no-store',
            headers: {
                'Content-Type': 'application/json',
                ...options?.headers,
            },
        });

        if (!response.ok) {
            const error = await response.json().catch(() => ({ detail: 'Unknown error' }));
            throw new ApiError(response.status, error.detail || `HTTP ${response.status}`);
        }

        if (response.status === 204) {
            return null as T;
        }

        return await response.json();
    } catch (error) {
        let status = 0;
        let message = 'Unknown error';

        if (error instanceof ApiError) {
            status = error.status;
            message = error.message;
        } else if (error instanceof Error) {
            message = error.message;
        }

        // Show native dialog for all errors
        const method = options?.method || 'GET';
        const handle = `${method} ${endpoint}`;
        await showAlert(
            `${handle} - ${status ? `${status} - ` : ''}${message}`,
            'Backend call failed'
        );

        if (error instanceof ApiError) {
            throw error;
        }
        throw new Error(`Network error: ${message}`);
    }
}

// Transaction API
export const transactionApi = {
    // List transactions with filters
    list: async (filters: {
        wallet_id?: number;
        classification?: Classification;
        limit?: number;
        skip?: number;
    } = {}): Promise<PopulatedTransaction[]> => {
        const params = new URLSearchParams();
        if (filters.wallet_id) params.append('wallet_id', filters.wallet_id.toString());
        if (filters.classification) params.append('classification', filters.classification);
        if (filters.limit) params.append('limit', filters.limit.toString());
        if (filters.skip) params.append('skip', filters.skip.toString());

        return fetchApi<PopulatedTransaction[]>(`/transactions/?${params.toString()}`);
    },

    // Get all transactions for a specific month
    getByMonth: async (year: number, month: number): Promise<PopulatedTransaction[]> => {
        // Format as YYYY-MM-01 for the month parameter
        const monthStr = `${year}-${String(month).padStart(2, '0')}-01`;
        return fetchApi<PopulatedTransaction[]>(`/transactions/?month=${monthStr}`);
    },

    // Get a single transaction by ID
    getById: async (id: number): Promise<PopulatedTransaction> => {
        return fetchApi<PopulatedTransaction>(`/transactions/${id}`);
    },

    // Create a new transaction
    create: async (data: CreateTransactionRequest): Promise<Transaction> => {
        return fetchApi<Transaction>('/transactions', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Update a transaction
    update: async (id: number, data: UpdateTransactionRequest): Promise<Transaction> => {
        return fetchApi<Transaction>(`/transactions/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },

    // Delete a transaction
    delete: async (id: number): Promise<void> => {
        return fetchApi<void>(`/transactions/${id}`, {
            method: 'DELETE',
        });
    },

    // Mark transaction as split payment
    markAsSplit: async (id: number, data: MarkAsSplitRequest): Promise<LinkedEntry> => {
        return fetchApi<LinkedEntry>(`/transactions/${id}/mark-split`, {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Mark transaction as loan
    markAsLoan: async (id: number, data: MarkAsLoanRequest): Promise<LinkedEntry> => {
        return fetchApi<LinkedEntry>(`/transactions/${id}/mark-loan`, {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Mark transaction as debt
    markAsDebt: async (id: number, data: MarkAsDebtRequest): Promise<LinkedEntry> => {
        return fetchApi<LinkedEntry>(`/transactions/${id}/mark-debt`, {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Unclassify transaction (remove split/loan/debt)
    unclassify: async (id: number): Promise<void> => {
        return fetchApi<void>(`/transactions/${id}/unclassify`, {
            method: 'POST',
        });
    },

    // Ignore transaction (exclude from budget)
    ignore: async (id: number): Promise<void> => {
        return fetchApi<void>('/transactions/ignore', {
            method: 'POST',
            body: JSON.stringify({ transaction_ids: [id] }),
        });
    },

    // Unignore transaction (include in budget)
    unignore: async (id: number): Promise<void> => {
        return fetchApi<void>('/transactions/unignore', {
            method: 'POST',
            body: JSON.stringify({ transaction_ids: [id] }),
        });
    },

    unlink: async (id: number): Promise<void> => {
        return fetchApi<void>(`/transactions/${id}/unlink`, {
            method: 'POST',
        });
    },

    // Resolve calibration transaction
    resolveCalibration: async (id: number, newTransaction: CreateTransactionRequest): Promise<{
        new_transaction: Transaction;
        calibration_deleted: boolean;
        updated_calibration: Transaction | null;
    }> => {
        return fetchApi(`/transactions/${id}/resolve`, {
            method: 'POST',
            body: JSON.stringify({ new_transaction: newTransaction }),
        });
    },

    // Reclassify transaction type
    reclassify: async (id: number, classification: Classification): Promise<Transaction> => {
        return fetchApi<Transaction>(`/transactions/${id}/reclassify`, {
            method: 'POST',
            body: JSON.stringify({ classification }),
        });
    },

    // Link transaction to pending entry
    linkToEntry: async (id: number, data: LinkToEntryRequest): Promise<void> => {
        return fetchApi<void>(`/linked-entries/${data.linked_entry_id}/link`, {
            method: 'POST',
            body: JSON.stringify({
                transaction_id: id
            }),
        });
    },

    // Bulk Delete
    deleteTransactions: async (ids: number[]): Promise<void> => {
        return fetchApi<void>('/transactions/', {
            method: 'DELETE',
            body: JSON.stringify({ transaction_ids: ids }),
        });
    },

    // Bulk Ignore
    ignoreTransactions: async (ids: number[]): Promise<void> => {
        return fetchApi<void>('/transactions/ignore', {
            method: 'POST',
            body: JSON.stringify({ transaction_ids: ids }),
        });
    },

    // Bulk Unignore
    unignoreTransactions: async (ids: number[]): Promise<void> => {
        return fetchApi<void>('/transactions/unignore', {
            method: 'POST',
            body: JSON.stringify({ transaction_ids: ids }),
        });
    },

    // Bulk Link
    linkTransactions: async (ids: number[], linkedEntryId: number): Promise<void> => {
        return fetchApi<void>('/transactions/link', {
            method: 'POST',
            body: JSON.stringify({
                transaction_ids: ids,
                linked_entry_id: linkedEntryId
            }),
        });
    },

    // Get monthly expenses
    getMonthlyExpenses: async (year: number, month: number): Promise<MonthlyExpenseResponse> => {
        return fetchApi<MonthlyExpenseResponse>(`/transactions/expenses/${year}/${month}`);
    },

    // Merge transactions
    merge: async (data: TransactionMergeRequest): Promise<Transaction> => {
        return fetchApi<Transaction>('/transactions/merge', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Bulk Import
    bulkImport: async (items: any[]): Promise<{ imported_count: number; message: string }> => {
        return fetchApi<{ imported_count: number; message: string }>('/transactions/bulk-import', {
            method: 'POST',
            body: JSON.stringify({ items }),
        });
    },
};

// Wallet API
export const walletApi = {
    // Get all wallets
    getAll: async (): Promise<Wallet[]> => {
        return fetchApi<Wallet[]>('/wallets');
    },

    // Get a single wallet by ID
    getById: async (id: number): Promise<Wallet> => {
        return fetchApi<Wallet>(`/wallets/${id}`);
    },

    // Create a new wallet
    create: async (data: { name: string; wallet_type: 'normal' | 'credit'; initial_balance?: number; credit_limit?: number }): Promise<Wallet> => {
        return fetchApi<Wallet>('/wallets', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Update a wallet
    update: async (id: number, data: { name?: string }): Promise<Wallet> => {
        return fetchApi<Wallet>(`/wallets/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },

    // Delete a wallet
    delete: async (id: number): Promise<void> => {
        return fetchApi<void>(`/wallets/${id}`, {
            method: 'DELETE',
        });
    },

    // Create a transfer between wallets
    transfer: async (data: CreateWalletTransferRequest): Promise<{ from: Transaction; to: Transaction }> => {
        return fetchApi<{ from: Transaction; to: Transaction }>('/wallets/transfer', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Calibrate wallet balance
    calibrate: async (walletId: number, correctBalance: number, miscCategoryId: number): Promise<Transaction> => {
        return fetchApi<Transaction>(`/wallets/${walletId}/calibrate`, {
            method: 'POST',
            body: JSON.stringify({
                correct_balance: correctBalance,
                misc_category_id: miscCategoryId,
            }),
        });
    },
};

// Category API
export const categoryApi = {
    // Get all categories
    getAll: async (): Promise<CategoryWithSubcategories[]> => {
        return fetchApi<CategoryWithSubcategories[]>('/categories');
    },

    // Get a single category by ID
    getById: async (id: number): Promise<Category> => {
        return fetchApi<Category>(`/categories/${id}`);
    },

    // Create a new category
    create: async (data: { name: string; emoji?: string }): Promise<Category> => {
        return fetchApi<Category>('/categories', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Update a category
    update: async (id: number, data: { name?: string; emoji?: string }): Promise<Category> => {
        return fetchApi<Category>(`/categories/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },

    // Delete a category
    delete: async (id: number, replacementCategoryId?: number, replacementSubcategoryId?: number): Promise<void> => {
        const params = new URLSearchParams();
        if (replacementCategoryId) params.append('replacement_category_id', replacementCategoryId.toString());
        if (replacementSubcategoryId) params.append('replacement_subcategory_id', replacementSubcategoryId.toString());

        const query = params.toString() ? `?${params.toString()}` : '';
        return fetchApi<void>(`/categories/${id}${query}`, {
            method: 'DELETE',
        });
    },
};

// Subcategory API
export const subcategoryApi = {
    // Get all subcategories for a category
    getByCategory: async (categoryId: number): Promise<Subcategory[]> => {
        return fetchApi<Subcategory[]>(`/categories/${categoryId}/subcategories`);
    },

    // Create a new subcategory
    create: async (categoryId: number, data: { name: string }): Promise<Subcategory> => {
        return fetchApi<Subcategory>(`/categories/${categoryId}/subcategories`, {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Update a subcategory
    update: async (id: number, data: { name?: string }): Promise<Subcategory> => {
        return fetchApi<Subcategory>(`/categories/subcategories/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },

    // Delete a subcategory
    delete: async (id: number, replacementCategoryId?: number, replacementSubcategoryId?: number): Promise<void> => {
        const params = new URLSearchParams();
        if (replacementCategoryId) params.append('replacement_category_id', replacementCategoryId.toString());
        if (replacementSubcategoryId) params.append('replacement_subcategory_id', replacementSubcategoryId.toString());

        const query = params.toString() ? `?${params.toString()}` : '';
        return fetchApi<void>(`/categories/subcategories/${id}${query}`, {
            method: 'DELETE',
        });
    },
};

// LinkedEntry API
export const linkedEntryApi = {
    // Get all pending linked entries
    getPending: async (): Promise<LinkedEntry[]> => {
        return fetchApi<LinkedEntry[]>('/linked-entries/pending');
    },

    // Get a single linked entry by ID
    getById: async (id: number): Promise<LinkedEntry> => {
        return fetchApi<LinkedEntry>(`/linked-entries/${id}`);
    },

    // Get linked entry by transaction ID
    getByTransaction: async (transactionId: number): Promise<LinkedEntry | null> => {
        return fetchApi<LinkedEntry | null>(`/linked-entries/transaction/${transactionId}`);
    },

    // Update a linked entry
    update: async (id: number, data: { counterparty_name?: string; user_amount?: number; notes?: string }): Promise<LinkedEntry> => {
        return fetchApi<LinkedEntry>(`/linked-entries/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },
};

// Budget API
export const budgetApi = {
    // Get all budgets with filters
    getAll: async (filters: {
        year?: number;
        month?: number;
        category_id?: number;
    } = {}): Promise<BudgetWithCategory[]> => {
        const params = new URLSearchParams();
        if (filters.year) params.append('year', filters.year.toString());
        if (filters.month) params.append('month', filters.month.toString());
        if (filters.category_id) params.append('category_id', filters.category_id.toString());

        return fetchApi<BudgetWithCategory[]>(`/budgets/?${params.toString()}`);
    },

    // Get a single budget by ID
    getById: async (id: number): Promise<BudgetWithCategory> => {
        return fetchApi<BudgetWithCategory>(`/budgets/${id}`);
    },

    // Create a new budget
    create: async (data: CreateBudgetRequest): Promise<Budget> => {
        return fetchApi<Budget>('/budgets', {
            method: 'POST',
            body: JSON.stringify(data),
        });
    },

    // Update a budget
    update: async (id: number, data: UpdateBudgetRequest): Promise<Budget> => {
        return fetchApi<Budget>(`/budgets/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
    },

    // Delete a budget
    delete: async (id: number): Promise<void> => {
        return fetchApi<void>(`/budgets/${id}`, {
            method: 'DELETE',
        });
    },

    // Get monthly summary
    getMonthlySummary: async (
        year: number,
        month: number,
        periodBoundaries: number[] = [7, 14, 21, 31]
    ): Promise<MonthlySummaryResponse> => {
        const boundaries = periodBoundaries.join(',');
        return fetchApi<MonthlySummaryResponse>(
            `/budgets/summary/${year}/${month}?period_boundaries=${boundaries}`
        );
    },
};

// Export all APIs
export const api = {
    transactions: transactionApi,
    wallets: walletApi,
    categories: categoryApi,
    subcategories: subcategoryApi,
    linkedEntries: linkedEntryApi,
    budgets: budgetApi,
};

export { ApiError };
