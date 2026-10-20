'use client';
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Info, X } from 'lucide-react';
import { Modal } from './companion-ui';
import type { MessageKey } from '../lib/i18n';
type T = (key: MessageKey) => string;
type Confirmation = { message: string; t: T };
const ConfirmationContext = createContext<((request: Confirmation) => Promise<boolean>) | null>(null);

export function OverlayProvider({ children }: { children: ReactNode }) {
    const [request, setRequest] = useState<Confirmation | null>(null);
    const resolve = useRef<((accepted: boolean) => void) | null>(null);
    const ask = useCallback((next: Confirmation) => {
        resolve.current?.(false);
        return new Promise<boolean>(done => { resolve.current = done; setRequest(next); });
    }, []);
    const finish = (accepted: boolean) => { const done = resolve.current; resolve.current = null; setRequest(null); done?.(accepted); };
    useEffect(() => () => { resolve.current?.(false); }, []);
    return <ConfirmationContext.Provider value={ask}>{children}{request && <Modal title={request.t('confirm')} close={() => finish(false)} t={request.t}><p className="confirmation-copy">{request.message}</p><div className="modal-actions"><button className="button" autoFocus onClick={() => finish(false)}>{request.t('cancel')}</button><button className="button primary" onClick={() => finish(true)}>{request.t('confirm')}</button></div></Modal>}</ConfirmationContext.Provider>;
}
export function useConfirm(t: T) {
    const ask = useContext(ConfirmationContext);
    if (!ask) throw new Error('Confirmation requires OverlayProvider');
    return (message: string) => ask({ message, t });
}

export function Toast({ message, close, t }: { message: string; close: () => void; t: T }) {
    const [host, setHost] = useState<HTMLElement | null>(null);
    const ref = useRef<HTMLDivElement>(null);
    useEffect(() => {
        const update = () => {
            const dialogs = document.querySelectorAll<HTMLDialogElement>('dialog[open]');
            setHost(dialogs.item(dialogs.length - 1) || document.body);
        };
        update();
        window.addEventListener('vita:overlay-change', update);
        return () => window.removeEventListener('vita:overlay-change', update);
    }, []);
    useEffect(() => {
        const element = ref.current;
        if (!element) return;
        element.showPopover();
        return () => { if (element.isConnected && element.matches(':popover-open')) element.hidePopover(); };
    }, [host]);
    return host ? createPortal(<div popover="manual" ref={ref} className="toast" role="status" aria-live="polite" aria-atomic="true"><Info size={18} className="toast-icon" aria-hidden="true"/><span>{message}</span><button type="button" className="icon-button" aria-label={t('close')} onClick={close}><X size={16}/></button></div>, host) : null;
}
