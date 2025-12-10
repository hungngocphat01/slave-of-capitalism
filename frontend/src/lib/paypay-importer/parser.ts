import type { RawCsvRow } from './types';

/**
 * Parse a single CSV line, handling quotes
 */
function parseValues(line: string): string[] {
    const values: string[] = [];
    let current = '';
    let inQuote = false;

    for (let i = 0; i < line.length; i++) {
        const char = line[i];

        if (char === '"') {
            const nextChar = line[i + 1];
            if (inQuote && nextChar === '"') {
                // Escaped quote
                current += '"';
                i++; // Skip next quote
            } else {
                // Toggle quote state
                inQuote = !inQuote;
            }
        } else if (char === ',' && !inQuote) {
            // End of field
            values.push(current);
            current = '';
        } else {
            current += char;
        }
    }

    // Push the last field
    values.push(current);

    return values;
}

/**
 * Parse CSV content string into an array of raw row objects
 * Manual implementation to avoid dependencies
 */
export function parseCsv(csvContent: string): RawCsvRow[] {
    // Remove BOM if present
    const content = csvContent.replace(/^\uFEFF/, '');

    // Split into lines
    let lines = content.split(/\r?\n/);

    // Remove empty lines at the end
    while (lines.length > 0 && lines[lines.length - 1].trim() === '') {
        lines.pop();
    }

    if (lines.length === 0) return [];

    // Parse headers
    const headers = parseValues(lines[0]);

    // Parse rows
    const rows: RawCsvRow[] = [];

    for (let i = 1; i < lines.length; i++) {
        const line = lines[i];
        if (!line.trim()) continue;

        const values = parseValues(line);
        const row: any = {};

        // Map values to headers
        for (let j = 0; j < headers.length; j++) {
            const header = headers[j];
            // Basic clean up of header name if needed
            const key = header.trim();
            row[key] = values[j] || '';
        }

        rows.push(row as RawCsvRow);
    }

    return rows;
}
