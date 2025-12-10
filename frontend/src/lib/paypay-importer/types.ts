// Re-export the relevant types from the expense-manager API
import type { CreateTransactionRequest, CreateWalletTransferRequest, Direction } from '../api/types';

// Re-export backend types for use within the library
export type { CreateTransactionRequest, CreateWalletTransferRequest, Direction };

export type ApiRequest = CreateTransactionRequest | CreateWalletTransferRequest;

// Raw CSV row structure (Japanese column names)
export interface RawCsvRow {
    '取引日': string;
    '出金金額（円）': string;
    '入金金額（円）': string;
    '取引内容': string;
    '取引先': string;
    '取引方法': string;
    '取引番号': string;
    // Other columns exist but we don't need them
    [key: string]: string;
}

// Transformed row with English columns
export interface TransformedRow {
    id: string;
    date: string;
    time: string;
    dayofweek: number;
    amount: number;
    direction: Direction;
    method: string;
    description: string;
    wallet: string;
    category?: string;
    wallet_id?: number;
}

// Rule compilation structures
export type RuleOperator = '>' | '<' | '=' | '>=' | '<=' | '*=';

export interface RuleCondition {
    field: string;
    operator: RuleOperator;
    value: string | number;
}

export interface CompiledRule {
    conditions: RuleCondition[];
    category: string;
}

// Input types for the importer
export interface CategoryMapEntry {
    category_id: number;
    subcategory_id?: number;
}

export interface ImporterConfig {
    csvContent: string;
    rules: string[];
    walletMapping: Record<string, number>;
    categoryMapping: Record<string, CategoryMapEntry>;
}

export interface ImportResult {
    rows: TransformedRow[];
    requests: ApiRequest[];
}
