'use client';
import { useEffect, useRef, useState } from 'react';
import { api } from './api';
export function changed() { window.dispatchEvent(new Event('vita:changed')); }
export function useResource(path: string | null, revision = 0, interval = 0) {
    const [data, setData] = useState<any>(null);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const [retry, setRetry] = useState(0);
    const [languageVersion, setLanguageVersion] = useState(0);
    const previousPath = useRef<string | null>(null);
    const hasData = useRef(false);
    useEffect(() => { const update = () => setLanguageVersion(n => n + 1); window.addEventListener('vita:locale', update); return () => window.removeEventListener('vita:locale', update); }, []);
    useEffect(() => {
        if (previousPath.current !== path) { setData(null); hasData.current = false; previousPath.current = path; }
        setError('');
        if (!path) { setData(null); hasData.current = false; setLoading(false); return; }
        let active = true;
        let running = false;
        let queued = false;
        let first = !hasData.current;
        const controller = new AbortController();
        async function fetchData() {
            if (document.hidden || !active) return;
            if (running) { queued = true; return; }
            running = true;
            if (first) setLoading(true);
            try {
                const result = await api(path!, { signal: controller.signal });
                if (active) { hasData.current = true; setData(result); setError(''); }
            } catch (e) {
                if (active) setError(e instanceof Error ? e.message : '');
            } finally {
                running = false;
                first = false;
                if (active) { setLoading(false); if (queued) { queued = false; void fetchData(); } }
            }
        }
        void fetchData();
        const timer = interval ? setInterval(fetchData, interval) : undefined;
        window.addEventListener('vita:changed', fetchData);
        window.addEventListener('focus', fetchData);
        document.addEventListener('visibilitychange', fetchData);
        return () => {
            active = false;
            controller.abort();
            clearInterval(timer);
            window.removeEventListener('vita:changed', fetchData);
            window.removeEventListener('focus', fetchData);
            document.removeEventListener('visibilitychange', fetchData);
        };
    }, [path, revision, retry, interval, languageVersion]);
    return { data, error, loading, reload: () => setRetry(n => n + 1) };
}
