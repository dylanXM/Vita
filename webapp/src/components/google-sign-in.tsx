'use client';

import { useEffect, useRef, useState } from 'react';
import { loadGoogleIdentity } from '../lib/google-auth';
import type { Locale, MessageKey } from '../lib/i18n';

type Props = {
  clientId: string;
  locale: Locale;
  disabled: boolean;
  loadingConfig: boolean;
  t: (key: MessageKey) => string;
  onCredential: (credential: string) => void;
  reloadConfig: () => void;
};

export default function GoogleSignIn({ clientId, locale, disabled, loadingConfig, t, onCredential, reloadConfig }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const callback = useRef(onCredential);
  const blocked = useRef(disabled);
  callback.current = onCredential;
  blocked.current = disabled;
  const [state, setState] = useState<'loading' | 'ready' | 'failed'>('loading');
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (!clientId) return;
    let active = true;
    let observer: ResizeObserver | undefined;
    const node = host.current;
    setState('loading');
    loadGoogleIdentity().then(identity => {
      if (!active || !node) return;
      identity.initialize({
        client_id: clientId, auto_select: false, ux_mode: 'popup',
        callback: response => {
          if (!active || blocked.current) return;
          if (response.credential) callback.current(response.credential);
          else setState('failed');
        },
      });
      let previousWidth = 0;
      const render = () => {
        const width = Math.min(400, Math.floor(node.clientWidth));
        if (width < 120 || width === previousWidth) return;
        previousWidth = width;
        node.replaceChildren();
        identity.renderButton(node, {
          theme: document.documentElement.dataset.theme === 'dark' ? 'filled_black' : 'outline',
          size: 'large', shape: 'pill', text: 'continue_with', width, locale,
        });
        setState('ready');
      };
      render();
      observer = new ResizeObserver(render);
      observer.observe(node);
    }).catch(() => { if (active) setState('failed'); });
    return () => { active = false; observer?.disconnect(); node?.replaceChildren(); };
  }, [clientId, locale, attempt]);

  const unavailable = !clientId && !loadingConfig;
  return <div className="google-auth" data-pending={!!clientId && state !== 'ready' || undefined}>
    <div ref={host} className="google-button-host" inert={disabled || state !== 'ready' || undefined} hidden={!clientId} style={{ visibility: state === 'ready' ? 'visible' : 'hidden' }} />
    {(!clientId || state !== 'ready') && <button type="button" className="google-button-fallback" disabled={disabled || loadingConfig || (!!clientId && state === 'loading')} onClick={() => { if (clientId) setAttempt(n => n + 1); else reloadConfig(); }}>
      <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true"><path fill="#4285F4" d="M43.61 24.46c0-1.36-.12-2.66-.35-3.92H24.4v7.42h10.77a9.2 9.2 0 0 1-4 6.03v5h6.46c3.79-3.49 5.98-8.63 5.98-14.53Z"/><path fill="#34A853" d="M24.4 44c5.4 0 9.93-1.79 13.24-4.85l-6.46-5c-1.79 1.2-4.08 1.93-6.78 1.93-5.21 0-9.63-3.52-11.21-8.26H6.52v5.16A19.99 19.99 0 0 0 24.4 44Z"/><path fill="#FBBC05" d="M13.19 27.82a12.01 12.01 0 0 1 0-7.64v-5.16H6.52a20 20 0 0 0 0 17.96l6.67-5.16Z"/><path fill="#EA4335" d="M24.4 11.92c2.94 0 5.56 1.01 7.65 3l5.73-5.74C34.31 5.95 29.8 4 24.4 4A19.99 19.99 0 0 0 6.52 15.02l6.67 5.16c1.58-4.74 6-8.26 11.21-8.26Z"/></svg>
      <span>{loadingConfig || (!!clientId && state === 'loading') ? t('loading') : state === 'failed' && clientId ? t('googleRetry') : t('googleContinue')}</span>
    </button>}
    {(unavailable || (clientId && state === 'failed')) && <p className="google-auth-error" role="status">{t(unavailable ? 'googleUnavailable' : 'googleLoadFailed')}</p>}
  </div>;
}
