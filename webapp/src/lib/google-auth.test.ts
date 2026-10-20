import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const backend = vi.hoisted(() => ({ api: vi.fn() }));
vi.mock('./api', () => backend);

type TestScript = { src: string; async: boolean; defer: boolean; onload: (() => void) | null; onerror: (() => void) | null; remove: ReturnType<typeof vi.fn> };
let scripts: TestScript[];
let browser: { google?: { accounts: { id: object } } };
const identity = { initialize: vi.fn(), renderButton: vi.fn() };

beforeEach(() => {
  vi.resetModules();
  backend.api.mockReset();
  scripts = [];
  browser = {};
  vi.stubGlobal('window', browser);
  vi.stubGlobal('document', {
    createElement: () => ({ src: '', async: false, defer: false, onload: null, onerror: null, remove: vi.fn() }),
    head: { appendChild: (script: TestScript) => { scripts.push(script); } },
  });
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe('Google SDK lifecycle', () => {
  it('shares a single script load for concurrent login consumers', async () => {
    const { loadGoogleIdentity } = await import('./google-auth');
    const first = loadGoogleIdentity();
    const second = loadGoogleIdentity();
    expect(second).toBe(first);
    expect(scripts).toHaveLength(1);
    expect(scripts[0].src).toBe('https://accounts.google.com/gsi/client');
    browser.google = { accounts: { id: identity } };
    scripts[0].onload?.();
    await expect(first).resolves.toBe(identity);
  });
  it('allows a clean retry after an SDK network failure', async () => {
    const { loadGoogleIdentity } = await import('./google-auth');
    const first = loadGoogleIdentity();
    const rejection = expect(first).rejects.toThrow('google_sdk_unavailable');
    scripts[0].onerror?.();
    await rejection;
    expect(scripts[0].remove).toHaveBeenCalledOnce();
    const retry = loadGoogleIdentity();
    expect(scripts).toHaveLength(2);
    browser.google = { accounts: { id: identity } };
    scripts[1].onload?.();
    await expect(retry).resolves.toBe(identity);
  });
  it('times out without leaving a permanently loading login button', async () => {
    vi.useFakeTimers();
    const { loadGoogleIdentity } = await import('./google-auth');
    const rejected = expect(loadGoogleIdentity()).rejects.toThrow('google_sdk_unavailable');
    await vi.advanceTimersByTimeAsync(15000);
    await rejected;
    expect(scripts[0].remove).toHaveBeenCalledOnce();
  });
});

describe('Google credential exchange', () => {
  it('sends the Google credential to Backend without implicitly accepting legal terms', async () => {
    const { exchangeGoogleCredential } = await import('./google-auth');
    backend.api.mockResolvedValue({ token: 'vita-access', refresh_token: 'vita-refresh' });
    const session = await exchangeGoogleCredential('google-id-token');
    expect(backend.api).toHaveBeenCalledWith('/v1/auth/google', {
      method: 'POST', signal: undefined, body: { id_token: 'google-id-token' },
    });
    expect(session.token).toBe('vita-access');
  });
  it('sends the reviewed document versions only after explicit consent', async () => {
    const { exchangeGoogleCredential } = await import('./google-auth');
    backend.api.mockResolvedValue({ token: 'vita-access', refresh_token: 'vita-refresh' });
    await exchangeGoogleCredential('google-id-token', { privacyVersion: 'privacy-v2', termsVersion: 'terms-v3', inviteCode: 'INVITE' });
    expect(backend.api.mock.calls[0][1].body).toEqual({
      id_token: 'google-id-token', accepted_legal: true,
      privacy_policy_version: 'privacy-v2', terms_version: 'terms-v3', invite_code: 'INVITE',
    });
  });
  it('rejects missing credentials or incomplete consent before a request', async () => {
    const { exchangeGoogleCredential } = await import('./google-auth');
    await expect(exchangeGoogleCredential('')).rejects.toThrow('google_credential_missing');
    await expect(exchangeGoogleCredential('token', { privacyVersion: '', termsVersion: 'v1' })).rejects.toThrow('google_consent_incomplete');
    expect(backend.api).not.toHaveBeenCalled();
  });
  it('preserves Backend consent errors for the registration confirmation flow', async () => {
    const { exchangeGoogleCredential } = await import('./google-auth');
    const error = Object.assign(new Error('Consent required'), { code: 'legal_consent_required' });
    backend.api.mockRejectedValue(error);
    await expect(exchangeGoogleCredential('google-id-token')).rejects.toBe(error);
  });
});
