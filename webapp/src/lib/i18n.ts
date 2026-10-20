import productCopy from './product-copy.json';
import webCopy from './web-copy.json';

export const localeNames = {
    'zh-CN': '简体中文', 'zh-TW': '繁體中文', en: 'English', es: 'Español',
    pt: 'Português', ja: '日本語', ko: '한국어', ar: 'العربية',
} as const;
export type Locale = keyof typeof localeNames;
export const messages = {
    'zh-CN': { ...productCopy['zh-CN'], ...webCopy['zh-CN'] },
    'zh-TW': { ...productCopy['zh-TW'], ...webCopy['zh-TW'] },
    en: { ...productCopy.en, ...webCopy.en },
    es: { ...productCopy.es, ...webCopy.es },
    pt: { ...productCopy.pt, ...webCopy.pt },
    ja: { ...productCopy.ja, ...webCopy.ja },
    ko: { ...productCopy.ko, ...webCopy.ko },
    ar: { ...productCopy.ar, ...webCopy.ar },
} as const;
export type MessageKey = keyof typeof messages.en;
export function productText(key: string, t: (key: MessageKey) => string): string {
    return Object.hasOwn(messages.en, key) ? t(key as MessageKey) : key;
}

export function displayDate(value: string, style: 'date' | 'time' | 'datetime' = 'datetime', options?: Intl.DateTimeFormatOptions): string {
    const date = new Date(value);
    const locale = typeof document === 'undefined' ? 'zh-CN' : document.documentElement.lang;
    if (style === 'date') return date.toLocaleDateString(locale, options);
    if (style === 'time') return date.toLocaleTimeString(locale, options);
    return date.toLocaleString(locale, options);
}
