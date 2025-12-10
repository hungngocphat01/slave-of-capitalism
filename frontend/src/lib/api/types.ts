// API Types based on backend models

export type Direction = 'inflow' | 'outflow';

export type Classification =
    | 'expense'
    | 'income'
    | 'lend'
    | 'borrow'
    | 'debt_collection'
    | 'loan_repayment'
    | 'split_payment'
    | 'transfer';

export type LinkType = 'split_payment' | 'loan' | 'debt';

export type LinkedEntryStatus = 'pending' | 'partial' | 'settled';

export type WalletType = 'normal' | 'credit';

export interface Transaction {
    id: number;
    date: string;
    time?: string;
    wallet_id: number;
    direction: Direction;
    amount: number;
    classification: Classification;
    description: string;
    category_id?: number;
    subcategory_id?: number;
    paired_transaction_id?: number;
    is_ignored: boolean;
    is_calibration: boolean;
    is_linked_to_entry?: boolean;
    created_at: string;
    updated_at: string;
}

export interface Wallet {
    id: number;
    name: string;
    wallet_type: WalletType;
    initial_balance?: number;
    credit_limit: number;
    current_balance: number;       // Calculated from backend
    available_credit?: number;     // Only for credit wallets
    emoji?: string;
    created_at: string;
    updated_at: string;
}

export interface Category {
    id: number;
    name: string;
    emoji?: string;
    color?: string;
    is_system: boolean;
    created_at: string;
    updated_at: string;
}

export interface CategoryWithSubcategories extends Category {
    subcategories: Subcategory[];
}

export interface Subcategory {
    id: number;
    category_id: number;
    name: string;
    is_system: boolean;
    created_at: string;
    updated_at: string;
}

export interface LinkedEntry {
    id: number;
    link_type: LinkType;
    primary_transaction_id: number;
    counterparty_name: string;
    total_amount: number;
    user_amount?: number;
    pending_amount: number;
    status: LinkedEntryStatus;
    notes?: string;
    created_at: string;
    updated_at: string;
    linked_transactions?: LinkedTransaction[];
    primary_transaction_description?: string;
    primary_transaction_date?: string;
}

export interface LinkedTransaction {
    id: number;
    linked_entry_id: number;
    transaction_id: number;
    amount: number;
    created_at: string;
    date?: string;
    description?: string;
}

// Request/Response types
export interface CreateTransactionRequest {
    date: string;
    time?: string;
    wallet_id: number;
    direction: Direction;
    amount: number;
    classification: Classification;
    description: string;
    category_id?: number;
    subcategory_id?: number;
    is_ignored?: boolean;
    is_calibration?: boolean;
}

export interface UpdateTransactionRequest {
    date?: string;
    time?: string;
    description?: string;
    amount?: number;
    wallet_id?: number;
    category_id?: number;
    subcategory_id?: number;
    classification?: Classification;
}

export interface CreateWalletTransferRequest {
    from_wallet_id: number;
    to_wallet_id: number;
    amount: number;
    date: string;
    time?: string;
    description?: string;
}

export interface MarkAsSplitRequest {
    counterparty_name: string;
    user_amount: number;
    notes?: string;
}

export interface MarkAsLoanRequest {
    counterparty_name: string;
    notes?: string;
}

export interface MarkAsDebtRequest {
    counterparty_name: string;
    notes?: string;
}

export interface LinkToEntryRequest {
    linked_entry_id: number;
}

export interface MonthlyExpenseResponse {
    year: number;
    month: number;
    total_expense: number;
    by_category: Record<string, number>;
}

export interface Budget {
    id: number;
    category_id: number;
    year: number;
    month: number;
    amount: number;
    created_at: string;
    updated_at: string;
}

export interface BudgetWithCategory extends Budget {
    category_name?: string;
    category_emoji?: string;
}

export interface CreateBudgetRequest {
    category_id: number;
    year: number;
    month: number;
    amount: number;
}

export interface UpdateBudgetRequest {
    amount?: number;
}

export interface SubcategorySummary {
    subcategory_id: number;
    subcategory_name: string;
    actual: number;
    periods: number[];
}

export interface CategorySummary {
    category_id: number;
    category_name: string;
    emoji?: string;
    budget: number;
    actual: number;
    percentage: number;
    periods: number[];
    subcategories: SubcategorySummary[];
}

export interface MonthlySummaryResponse {
    year: number;
    month: number;
    categories: CategorySummary[];
    total_budget: number;
    total_actual: number;
    period_boundaries: number[];
}

// Populated types (with related data)

export interface PopulatedTransaction extends Transaction {
    wallet?: Wallet;
    category?: Category;
    subcategory?: Subcategory;
    paired_transaction?: Transaction;
    linked_entry?: LinkedEntry;
}

export interface TransactionMergeRequest {
    transaction_ids: number[];
    date: string;
    description: string;
    category_id?: number | null;
    subcategory_id?: number | null;
}
