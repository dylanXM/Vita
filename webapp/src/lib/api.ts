export interface Entity {
    [key: string]: any;
}
export const baseURL = (process.env.NEXT_PUBLIC_VITA_API_URL || '').replace(/\/$/, '');
let refreshing: Promise<boolean> | null = null;
export class ApiError extends Error {
    constructor(message: string, public status: number, public code?: string, public action?: string) { super(message); }
}
export const session = {
    exists: () => typeof window !== 'undefined' && !!localStorage.getItem('vita.token'),
    write(data: Entity) {
        if (!data.token || !data.refresh_token)
            throw new Error('Invalid session response');
        localStorage.setItem('vita.token', data.token);
        localStorage.setItem('vita.refresh', data.refresh_token);
    },
    clear() { localStorage.removeItem('vita.token'); localStorage.removeItem('vita.refresh'); },
};
async function refresh() {
    if (!refreshing)
        refreshing = (async () => {
            const token = localStorage.getItem('vita.refresh');
            if (!token)
                return false;
            const response = await fetch(`${baseURL}/v1/auth/refresh`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: token }), signal: AbortSignal.timeout(20000) });
            if (!response.ok)
                return false;
            session.write(await response.json());
            return true;
        })().finally(() => { refreshing = null; });
    return refreshing;
}
export async function api(path: string, options: {
    method?: string;
    body?: Entity | FormData;
    signal?: AbortSignal;
} = {}, retried = false): Promise<any> {
    const headers: Record<string, string> = { 'X-Vita-Platform': 'web', 'X-Vita-App-Version': '0.1.0', 'Accept-Language': localStorage.getItem('vita.locale') || 'zh-CN' };
    const token = localStorage.getItem('vita.token');
    if (token)
        headers.Authorization = `Bearer ${token}`;
    if (!(options.body instanceof FormData))
        headers['Content-Type'] = 'application/json';
    const response = await fetch(`${baseURL}${path}`, { method: options.method || 'GET', headers, body: options.body instanceof FormData ? options.body : options.body ? JSON.stringify(options.body) : undefined, signal: options.signal || AbortSignal.timeout(90000), cache: 'no-store' });
    if (response.status === 401 && !path.startsWith('/v1/auth/') && !retried) {
        let renewed = false;
        try {
            renewed = await refresh();
        }
        catch { /* Expired or unavailable refresh session. */ }
        if (renewed)
            return api(path, options, true);
        session.clear();
        window.dispatchEvent(new Event('vita:expired'));
    }
    const data = await response.json().catch(() => ({}));
    if (!response.ok)
        throw new ApiError(data.error || `Request failed (${response.status})`, response.status, data.code, data.action);
    return data;
}
export function items(data: any, key = 'items'): Entity[] { return Array.isArray(data) ? data : Array.isArray(data?.[key]) ? data[key] : []; }
export function safeURL(value: unknown): string {
    if (typeof value !== 'string')
        return '';
    if (value.startsWith('asset://assets/ai_pets/') && ['cat_orange.png', 'cat_ragdoll.png', 'cat_tuxedo.png', 'dog_corgi.png', 'dog_retriever.png', 'dog_shiba.png'].includes(value.slice('asset://assets/ai_pets/'.length)))
        return value.replace('asset://', '/');
    if (value.startsWith('/v1/'))
        return `${baseURL}${value}`;
    try {
        const url = new URL(value);
        return ['https:', 'http:'].includes(url.protocol) ? url.href : '';
    }
    catch {
        return '';
    }
}
