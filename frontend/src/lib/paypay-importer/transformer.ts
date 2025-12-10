import type { RawCsvRow, TransformedRow, Direction } from './types';
import { translateMethod } from './translator';

/**
 * Parse Japanese number format (with commas) to number
 * Handles null/undefined/empty string cases
 */
function parseJapaneseNumber(value: string | undefined | null): number {
    if (!value || value === '-') {
        return 0;
    }
    // Remove commas and convert to number
    return parseFloat(value.replace(/,/g, ''));
}

/**
 * Manual date formatting to avoid date-fns dependency
 * Format: yyyy-MM-dd
 */
function formatDate(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

/**
 * Manual time formatting
 * Format: HH:mm:ss
 */
function formatTime(date: Date): string {
    const h = String(date.getHours()).padStart(2, '0');
    const m = String(date.getMinutes()).padStart(2, '0');
    const s = String(date.getSeconds()).padStart(2, '0');
    return `${h}:${m}:${s}`;
}

/**
 * Transform raw CSV rows into processed rows with English columns
 */
export function transformRows(rawRows: RawCsvRow[]): TransformedRow[] {
    return rawRows.map(row => {
        // Parse datetime: "2025/12/10 12:17:20"
        // Native Date constructor handles "yyyy/MM/dd HH:mm:ss" well in most browsers, 
        // but replacing '/' with '-' is safer for standard ISO parsing if needed.
        // Actually "2025/12/10 12:17:20" is standard in JS.
        const datetimeStr = row['取引日'];
        const datetime = new Date(datetimeStr);

        const date = formatDate(datetime);
        const time = formatTime(datetime);
        const dayofweek = datetime.getDay(); // 0-6, Sunday = 0

        // Parse amounts
        const inflow = parseJapaneseNumber(row['入金金額（円）']);
        const outflow = parseJapaneseNumber(row['出金金額（円）']);

        // Determine amount and direction
        const amount = Math.max(inflow, outflow);
        const direction: Direction = inflow > 0 ? 'inflow' : 'outflow';

        // Translate method
        const methodJapanese = row['取引内容'];
        const method = translateMethod(methodJapanese);

        return {
            id: row['取引番号'],
            date,
            time,
            dayofweek,
            amount,
            direction,
            method,
            description: row['取引先'],
            wallet: row['取引方法'],
        };
    });
}
