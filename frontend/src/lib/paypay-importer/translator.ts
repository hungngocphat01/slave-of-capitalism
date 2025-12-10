// Translation mappings for the method field (取引内容)
export const METHOD_TRANSLATIONS: Record<string, string> = {
    '支払い': 'payment',
    '受け取った金額': 'received',
    '送った金額': 'sent',
    'チャージ': 'charge',
    '口座送金': 'bank_transfer',
};

/**
 * Translate Japanese method text to English
 */
export function translateMethod(japaneseMethod: string): string {
    return METHOD_TRANSLATIONS[japaneseMethod] || japaneseMethod;
}
