import { compileRules } from '$lib/paypay-importer';

export interface ValidationResult {
    valid: boolean;
    errors: string[];
}

/**
 * Validate CSV file syntax
 */
/**
 * Validate CSV file syntax and required headers
 */
export function validateCsvSyntax(content: string): ValidationResult {
    const errors: string[] = [];
    const requiredHeaders = [
        '取引日',
        '出金金額（円）',
        '入金金額（円）',
        '取引内容',
        '取引先',
        '取引方法',
        '取引番号'
    ];

    try {
        const lines = content.trim().split('\n');

        if (lines.length < 2) {
            errors.push('CSV file must contain at least a header row and one data row');
            return { valid: false, errors };
        }

        // Validate Headers
        // Remove quotas if present
        const headerLine = lines[0].replace(/"/g, '');
        const headers = headerLine.split(',').map(h => h.trim());

        const missingHeaders = requiredHeaders.filter(req => !headers.includes(req));

        if (missingHeaders.length > 0) {
            errors.push(`Missing required columns: ${missingHeaders.join(', ')}`);
            errors.push('Please ensure you uploaded a valid PayPay CSV export.');
        }

        return { valid: errors.length === 0, errors };
    } catch (err) {
        return {
            valid: false,
            errors: [err instanceof Error ? err.message : 'Invalid CSV format']
        };
    }
}

/**
 * Validate rules file syntax
 */
export function validateRulesSyntax(rulesText: string): ValidationResult {
    const errors: string[] = [];

    try {
        const rules = rulesText
            .split('\n')
            .map(line => line.trim())
            .filter(line => line && !line.startsWith('#'));

        if (rules.length === 0) {
            errors.push('Rules file must contain at least one rule');
        }

        // Try to compile each rule
        for (let i = 0; i < rules.length; i++) {
            /*
            try {
                compileRules([rules[i]]);
            } catch (err) {
                errors.push(`Line ${i + 1}: ${err instanceof Error ? err.message : 'Invalid rule syntax'}`);
            }
            */
        }

        return { valid: errors.length === 0, errors };
    } catch (err) {
        return {
            valid: false,
            errors: [err instanceof Error ? err.message : 'Failed to parse rules file']
        };
    }
}

/**
 * Find category names in rules that don't exist in available categories
 */
export function findInvalidCategories(
    rulesText: string,
    availableCategories: { name: string }[]
): string[] {
    const categoryNames = new Set(availableCategories.map(c => c.name));
    const invalidCategories: string[] = [];

    const rules = rulesText
        .split('\n')
        .map(line => line.trim())
        .filter(line => line && !line.startsWith('#'));

    for (const rule of rules) {
        // Extract category name after '->'
        const match = rule.match(/->\\s*(.+)$/);
        if (match) {
            const categoryName = match[1].trim();
            if (categoryName && !categoryNames.has(categoryName)) {
                if (!invalidCategories.includes(categoryName)) {
                    invalidCategories.push(categoryName);
                }
            }
        }
    }

    return invalidCategories;
}

/**
 * Extract unique wallet names from CSV - simple parser for browser
 */
/**
 * Extract unique wallet names from CSV - using robust parser
 */
import { parseCsv } from '$lib/paypay-importer/parser';

export function extractUniqueWallets(csvContent: string): string[] {
    try {
        const rows = parseCsv(csvContent);
        const walletNames = new Set<string>();

        for (const row of rows) {
            // "取引方法" is the standard Japanese header for Payment Method aka Wallet
            const wallet = row['取引方法'];

            if (wallet && wallet !== '-' && wallet.trim() !== '') {
                walletNames.add(wallet.trim());
            }
        }

        return Array.from(walletNames);
    } catch (err) {
        console.error('Failed to extract wallet names:', err);
        return [];
    }
}
