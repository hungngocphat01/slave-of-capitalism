import type { CompiledRule, TransformedRow } from './types';

/**
 * Execute a single condition on a row
 */
function evaluateCondition(row: TransformedRow, condition: any): boolean {
    const { field, operator, value } = condition;

    // Get the field value from the row
    const rowValue = (row as any)[field];

    if (rowValue === undefined) {
        return false;
    }

    // Compare based on operator
    switch (operator) {
        case '>':
            return rowValue > value;
        case '<':
            return rowValue < value;
        case '>=':
            return rowValue >= value;
        case '<=':
            return rowValue <= value;
        case '=':
            // For string comparison, convert both to string
            return String(rowValue) === String(value);
        case '*=':
            // Substring matching - check if rowValue contains value
            return String(rowValue).includes(String(value));
        default:
            return false;
    }
}

/**
 * Check if a row matches all conditions in a rule (AND logic)
 */
function matchesRule(row: TransformedRow, rule: CompiledRule): boolean {
    return rule.conditions.every(condition => evaluateCondition(row, condition));
}

/**
 * Apply built-in automated rules
 */
function applyAutomatedRules(rows: TransformedRow[]): void {
    for (const row of rows) {
        if (row.method === 'charge' || row.method === 'bank_transfer') {
            row.category = '';
        }
    }
}

/**
 * Check if a rule has a method condition
 */
function hasMethodCondition(rule: CompiledRule): boolean {
    return rule.conditions.some(condition => condition.field === 'method');
}

/**
 * Execute all rules on the transformed rows
 * Rules are applied in order, and only uncategorized rows are matched
 * 
 * Note: Unless explicitly specified, all user rules implicitly include method = "payment"
 */
export function executeRules(rows: TransformedRow[], compiledRules: CompiledRule[]): void {
    // First apply automated rules
    applyAutomatedRules(rows);

    // Then apply user-defined rules
    for (const rule of compiledRules) {
        // Check if rule has explicit method condition
        const requiresPaymentMethod = !hasMethodCondition(rule);

        for (const row of rows) {
            // Only process uncategorized rows
            if (row.category === undefined) {
                // If rule doesn't specify method, only match payment transactions
                if (requiresPaymentMethod && row.method !== 'payment') {
                    continue;
                }

                if (matchesRule(row, rule)) {
                    row.category = rule.category;
                }
            }
        }
    }
}
