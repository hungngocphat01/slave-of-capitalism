import type { CompiledRule, RuleCondition, RuleOperator } from './types';

/**
 * Parse a rule string and compile it to executable structure
 * Example: "time > 15:00, amount < 500 -> Market groceries"
 */
export function compileRule(ruleString: string): CompiledRule {
    const parts = ruleString.split('->').map(p => p.trim());

    if (parts.length !== 2) {
        throw new Error(`Invalid rule syntax: ${ruleString}`);
    }

    const [conditionsStr, category] = parts;
    const conditions = parseConditions(conditionsStr);

    return {
        conditions,
        category,
    };
}

/**
 * Parse conditions string into array of condition objects
 * Example: "time > 15:00, amount < 500"
 */
function parseConditions(conditionsStr: string): RuleCondition[] {
    return conditionsStr.split(',').map(condStr => {
        const trimmed = condStr.trim();

        // Try to match operators (order matters - longer first)
        const operators: RuleOperator[] = ['>=', '<=', '*=', '>', '<', '='];

        for (const op of operators) {
            const idx = trimmed.indexOf(op);
            if (idx !== -1) {
                const field = trimmed.substring(0, idx).trim();
                const valueStr = trimmed.substring(idx + op.length).trim();

                // Parse value - remove quotes if present, otherwise try to parse as number
                let value: string | number;
                if (valueStr.startsWith('"') && valueStr.endsWith('"')) {
                    value = valueStr.slice(1, -1);
                } else if (valueStr.includes(':')) {
                    // If it contains a colon, treat as string (e.g., time like "15:00")
                    value = valueStr;
                } else if (!isNaN(parseFloat(valueStr)) && valueStr === String(parseFloat(valueStr))) {
                    // Only parse as number if the entire string is a valid number
                    value = parseFloat(valueStr);
                } else {
                    value = valueStr;
                }

                return {
                    field,
                    operator: op,
                    value,
                };
            }
        }

        throw new Error(`Invalid condition syntax: ${trimmed}`);
    });
}

/**
 * Compile multiple rule strings
 */
export function compileRules(ruleStrings: string[]): CompiledRule[] {
    return ruleStrings.map(rule => compileRule(rule));
}
