import { describe, expect, it } from 'vitest';
import Home from './page';
import { messages } from '../lib/i18n';
import { items, safeURL } from '../lib/api';
describe('Web application contract', () => {
    it('mounts the interactive application', () => { expect(typeof Home().type).toBe('function'); });
    it('keeps all eight translation dictionaries aligned', () => {
        expect(Object.keys(messages)).toHaveLength(8);
        for (const locale of Object.values(messages))
            expect(Object.keys(locale).sort()).toEqual(Object.keys(messages.en).sort());
        for (const locale of Object.values(messages))
            for (const value of Object.values(locale))
                expect(value.trim().length).toBeGreaterThan(0);
    });
    it('accepts additive list envelopes and missing lists', () => {
        expect(items({ items: [{ id: '1' }], extra: true })).toEqual([{ id: '1' }]);
        expect(items({ memories: [{ id: '2' }] }, 'memories')).toEqual([{ id: '2' }]);
        expect(items(null)).toEqual([]);
    });
    it('blocks executable or non-HTTP media URLs', () => {
        expect(safeURL('javascript:alert(1)')).toBe('');
        expect(safeURL('//evil.test/a')).toBe('');
        expect(safeURL('https://example.com/a.png')).toBe('https://example.com/a.png');
    });
});
