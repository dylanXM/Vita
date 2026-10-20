import { api, type Entity } from './api';

export interface GoogleIdentity {
  initialize(options: { client_id: string; callback: (response: { credential?: string }) => void; auto_select: boolean; ux_mode: 'popup' }): void;
  renderButton(element: HTMLElement, options: { theme: 'outline' | 'filled_black'; size: 'large'; shape: 'pill'; text: 'continue_with'; width: number; locale: string }): void;
}

type GoogleWindow = Window & { google?: { accounts?: { id?: GoogleIdentity } } };
let loading: Promise<GoogleIdentity> | null = null;

export function loadGoogleIdentity(): Promise<GoogleIdentity> {
  const available = (window as GoogleWindow).google?.accounts?.id;
  if (available) return Promise.resolve(available);
  if (loading) return loading;
  loading = new Promise<GoogleIdentity>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.async = true;
    script.defer = true;
    const fail = () => {
      clearTimeout(timeout);
      script.onload = null;
      script.onerror = null;
      script.remove();
      reject(new Error('google_sdk_unavailable'));
    };
    const timeout = setTimeout(fail, 15000);
    script.onload = () => {
      const identity = (window as GoogleWindow).google?.accounts?.id;
      if (!identity) { fail(); return; }
      clearTimeout(timeout);
      script.onload = null;
      script.onerror = null;
      resolve(identity);
    };
    script.onerror = fail;
    document.head.appendChild(script);
  }).catch(error => { loading = null; throw error; });
  return loading;
}

export interface GoogleConsent {
  privacyVersion: string;
  termsVersion: string;
  inviteCode?: string;
}

// The ID token is exchanged with Backend; it never becomes a Vita session itself.
export function exchangeGoogleCredential(credential: string, consent?: GoogleConsent, signal?: AbortSignal): Promise<Entity> {
  if (!credential) return Promise.reject(new Error('google_credential_missing'));
  if (consent && (!consent.privacyVersion || !consent.termsVersion)) return Promise.reject(new Error('google_consent_incomplete'));
  return api('/v1/auth/google', {
    method: 'POST', signal,
    body: {
      id_token: credential,
      ...(consent ? {
        accepted_legal: true,
        privacy_policy_version: consent.privacyVersion,
        terms_version: consent.termsVersion,
        ...(consent.inviteCode ? { invite_code: consent.inviteCode } : {}),
      } : {}),
    },
  });
}
