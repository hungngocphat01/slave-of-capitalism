import type { TransformedRow, ApiRequest, CreateTransactionRequest, CreateWalletTransferRequest } from './types';

/**
 * Transform categorized rows into API request objects
 */
/**
 * Transform categorized rows into API request objects
 */
export function emitRequests(
    rows: TransformedRow[],
    categoryMapping: Record<string, { category_id: number; subcategory_id?: number }>,
    walletMapping: Record<string, number>
): ApiRequest[] {
    return rows.flatMap((row): ApiRequest[] => {
        // Handle bank_transfer as ignored expense
        if (row.method === 'bank_transfer') {
            return [{
                date: row.date,
                time: row.time,
                wallet_id: row.wallet_id || 0,
                direction: 'outflow',
                amount: row.amount,
                classification: 'expense',
                description: row.description,
                is_ignored: true,
                is_calibration: false
            }];
        }

        // Handle charge (transfer from external wallet to PayPay Balance)
        if (row.method === 'charge') {
            return [createWalletTransferRequest(row, walletMapping)];
        }

        // Regular transaction
        return [createTransactionRequest(row, categoryMapping)];
    });
}

/**
 * Create a wallet transfer request (Charge)
 */
function createWalletTransferRequest(
    row: TransformedRow,
    walletMapping: Record<string, number>
): CreateWalletTransferRequest {
    // For Charge:
    // From: The wallet specified in the row (e.g. Bank Account)
    // To: PayPay Balance (PayPay残高)

    const fromWalletId = row.wallet_id || 0;

    // Find ID for "PayPay残高"
    // We assume the user has mapped "PayPay残高" (standard name) in the wizard
    const payPayBalanceId = walletMapping['PayPay残高'] || 0;

    return {
        from_wallet_id: fromWalletId,
        to_wallet_id: payPayBalanceId,
        amount: row.amount,
        date: row.date,
        time: row.time,
        description: row.description,
    };
}

/**
 * Create a transaction request
 */
function createTransactionRequest(
    row: TransformedRow,
    categoryMapping: Record<string, { category_id: number; subcategory_id?: number }>
): CreateTransactionRequest {
    // Map category name to IDs
    let category_id: number | undefined;
    let subcategory_id: number | undefined;

    if (row.category) {
        const mapping = categoryMapping[row.category];
        if (mapping) {
            category_id = mapping.category_id;
            subcategory_id = mapping.subcategory_id;
        }
    }

    return {
        date: row.date,
        time: row.time,
        wallet_id: row.wallet_id || 0,
        direction: row.direction,
        amount: row.amount,
        // Classification is mandatory in strict type (not nullable in interface?), 
        // but looking at interface: classification: Classification.
        // And Classification = 'expense' | 'income' ...
        // We default to 'expense' for payments.
        // If row.direction is 'inflow', it might be 'income'.
        classification: row.direction === 'inflow' ? 'income' : 'expense',
        description: row.description,
        category_id,
        subcategory_id,
        // Optional fields
        is_ignored: false,
        is_calibration: false
    };
}
