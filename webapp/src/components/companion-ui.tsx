'use client';
import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { UserRound, X } from 'lucide-react';
import { baseURL, safeURL } from '../lib/api';
import type { MessageKey } from '../lib/i18n';
type T = (key: MessageKey) => string;
export function Media({ src, kind = 'image', alt = '', className = '' }: {
    src?: string;
    kind?: string;
    alt?: string;
    className?: string;
}) {
    const url = useMediaURL(src);
    const [failed, setFailed] = useState<string>();
    if (!url || failed === src)
        return <div className={`media-placeholder ${className}`}><UserRound size={30}/></div>;
    if (kind === 'voice' || kind === 'audio')
        return <audio className={className} controls src={url}/>;
    if (kind === 'video')
        return <video className={className} controls playsInline src={url}/>;
    return <img className={className} src={url} alt={alt} loading="lazy" onError={() => setFailed(src)}/>;
}
export function Modal({ title, close, children, t, wide }: {
    title: string;
    close: () => void;
    wide?: boolean;
    children: ReactNode;
    t: T;
}) {
    const dialog = useRef<HTMLDialogElement>(null);
    const titleID = useId();
    useEffect(() => { const element = dialog.current; element?.showModal(); window.dispatchEvent(new Event('vita:overlay-change')); return () => { element?.close(); window.dispatchEvent(new Event('vita:overlay-change')); }; }, []);
    return <dialog className={wide ? "wide-dialog" : undefined} ref={dialog} aria-labelledby={titleID} onCancel={e => { e.preventDefault(); close(); }} onClick={e => {
            if (e.target === e.currentTarget) {
                const bounds = e.currentTarget.getBoundingClientRect();
                if (e.clientX < bounds.left || e.clientX > bounds.right || e.clientY < bounds.top || e.clientY > bounds.bottom) close();
            }
        }}><div className="modal-head"><h2 id={titleID}>{title}</h2><button className="icon-button" onClick={close} aria-label={t('close')}><X size={20}/></button></div>{children}</dialog>;
}

export function useMediaURL(src?: string) {
    const [url, setURL] = useState('');
    useEffect(() => {
        let active = true;
        let objectURL = '';
        const controller = new AbortController();
        const value = safeURL(src);
        setURL('');
        if (!value)
            return;
        const parsed = new URL(value, window.location.origin);
        if (parsed.pathname.startsWith('/v1/media/') || parsed.pathname.startsWith('/v1/encounters/media/')) {
            const headers: Record<string, string> = {};
            if (parsed.origin === new URL(baseURL || window.location.origin).origin)
                headers.Authorization = `Bearer ${localStorage.getItem('vita.token') || ''}`;
            fetch(value, { headers, signal: controller.signal }).then(r => {
                if (!r.ok)
                    throw Error();
                return r.blob();
            }).then(blob => {
                objectURL = URL.createObjectURL(blob);
                if (active)
                    setURL(objectURL);
                else
                    URL.revokeObjectURL(objectURL);
            }).catch(() => { });
        }
        else
            setURL(value);
        return () => {
            active = false;
            controller.abort();
            if (objectURL)
                URL.revokeObjectURL(objectURL);
        };
    }, [src]);
    return url;
}
