import type { TransformedRow } from './types';

/**
 * Map wallet names to wallet IDs using the provided mapping
 * Supports partial matching (e.g., "PayPay" matches "PayPay残高")
 */
export function mapWallets(rows: TransformedRow[], walletMapping: Record<string, number>): void {
    for (const row of rows) {
        const walletName = row.wallet;

        // First try exact match
        if (walletMapping[walletName] !== undefined) {
            row.wallet_id = walletMapping[walletName];
            continue;
        }

        // Then try partial match - find first mapping key that appears in the wallet name
        for (const [key, id] of Object.entries(walletMapping)) {
            if (walletName.includes(key)) {
                row.wallet_id = id;
                break;
            }
        }

        // If no match found, wallet_id remains undefined
    }
}
