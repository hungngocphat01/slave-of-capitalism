import { parseCsv } from './parser';
import { transformRows } from './transformer';
import { compileRules } from './rule-compiler';
import { executeRules } from './rule-executor';
import { mapWallets } from './wallet-mapper';
import { emitRequests } from './request-emitter';
import type { ApiRequest, ImporterConfig, ImportResult, CategoryMapEntry } from './types';

export class PayPayImporter {
    async importCsv(config: ImporterConfig): Promise<ImportResult> {
        const { csvContent, rules, walletMapping, categoryMapping } = config;

        // 1. Parse CSV content
        const rawRows = parseCsv(csvContent);

        // 2. Transform rows
        const transformedRows = transformRows(rawRows);

        // 3. Compile rules
        const compiledRules = compileRules(rules);

        // 4. Execute rules
        executeRules(transformedRows, compiledRules);

        // 5. Map wallet names
        mapWallets(transformedRows, walletMapping);

        // 6. Emit requests
        const requests = emitRequests(transformedRows, categoryMapping, walletMapping);

        return {
            rows: transformedRows,
            requests
        };
    }
}

export async function importPayPayCsv(
    csvContent: string,
    rules: string[],
    walletMapping: Record<string, number>,
    categoryMapping: Record<string, CategoryMapEntry>
): Promise<ImportResult> {
    const importer = new PayPayImporter();
    return importer.importCsv({
        csvContent,
        rules,
        walletMapping,
        categoryMapping,
    });
}

// Re-exports
export * from './types';
export { compileRules } from './rule-compiler';
