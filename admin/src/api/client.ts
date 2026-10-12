import axios, { type AxiosRequestConfig } from "axios";
import { getLocale } from "@/i18n";

/** localStorage key for the admin access token. */
export const TOKEN_KEY = "vita_admin_token";
const REFRESH_KEY = "vita_admin_refresh_token";
let sessionVersion = 0;

export function getRefreshToken(): string | null {
  return localStorage.getItem(REFRESH_KEY);
}
export function setSession(tokens: { token: string; refresh_token?: string }) {
  ++sessionVersion;
  localStorage.setItem(TOKEN_KEY, tokens.token);
  if (tokens.refresh_token) localStorage.setItem(REFRESH_KEY, tokens.refresh_token);
  else localStorage.removeItem(REFRESH_KEY);
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else {
    ++sessionVersion;
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(REFRESH_KEY);
  }
}

// The Vita API. In dev this is /v1 (proxied by Vite to the backend → no CORS).
// In a cross-origin deploy set VITE_API_BASE_URL to the absolute /v1 base.
const baseURL = import.meta.env.VITE_API_BASE_URL || "/v1";

export const api = axios.create({ baseURL, timeout: 30_000 });

// Attach the bearer token + the active UI locale on every request.
api.interceptors.request.use((config) => {
  config.headers = config.headers ?? {};
  const token = getToken();
  if (token) config.headers.Authorization = `Bearer ${token}`;
  config.headers["Accept-Language"] = getLocale();
  return config;
});

// One rotating refresh request per browser session. Web Locks serialize tabs
// because replaying the same refresh token revokes the backend session.
const refreshApi = axios.create({ baseURL, timeout: 30_000 });
let refreshing: Promise<string> | null = null;

function expireSession() {
  setToken(null);
  if (!window.location.pathname.startsWith("/login")) {
    const here = window.location.pathname + window.location.search;
    window.location.assign(`/login?redirect=${encodeURIComponent(here)}`);
  }
}

async function refreshAccessToken(failedToken: string): Promise<string> {
  if (refreshing) return refreshing;
  const version = sessionVersion;
  const perform = async () => {
    const current = getToken();
    if (sessionVersion !== version || !current) throw new Error("Session changed");
    if (current !== failedToken) return current;
    const refresh = getRefreshToken();
    if (!refresh) { expireSession(); throw new Error("Session expired"); }
    try {
      const { data } = await refreshApi.post<{ token: string; refresh_token: string }>(
        "/auth/refresh", { refresh_token: refresh });
      if (sessionVersion !== version || getRefreshToken() !== refresh) throw new Error("Session changed");
      if (!data.token || !data.refresh_token) throw new Error("Invalid refresh response");
      setSession(data);
      return data.token;
    } catch (error) {
      if (axios.isAxiosError(error) && error.response?.status === 401 &&
          sessionVersion === version && getRefreshToken() === refresh) expireSession();
      throw error;
    }
  };
  const operation = navigator.locks
    ? navigator.locks.request("vita-admin-token-refresh", perform)
    : perform();
  refreshing = operation;
  try { return await operation; } finally { if (refreshing === operation) refreshing = null; }
}

api.interceptors.response.use(
  res => res,
  async error => {
    const config = error.config as (AxiosRequestConfig & { _retried?: boolean }) | undefined;
    if (error.response?.status !== 401 || !config || config.url?.startsWith("/auth/")) {
      return Promise.reject(error);
    }
    const authorization = String(config.headers?.Authorization ?? "");
    const failedToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!failedToken || !getToken()) return Promise.reject(error);
    if (config._retried) {
      if (getToken() === failedToken) expireSession();
      return Promise.reject(error);
    }
    config._retried = true;
    const token = await refreshAccessToken(failedToken);
    config.headers = { ...config.headers, Authorization: `Bearer ${token}` };
    return api.request(config);
  },
);

/** Pull a human-readable message out of an axios error. */
export function errorMessage(err: unknown, fallback = "Something went wrong"): string {
  if (axios.isAxiosError(err)) {
    const data = err.response?.data as { error?: string; message?: string } | undefined;
    return data?.error || data?.message || err.message || fallback;
  }
  if (err instanceof Error) return err.message;
  return fallback;
}

// Thin typed helpers that unwrap response.data (the API returns bare JSON).
export const http = {
  get: async <T>(url: string, config?: AxiosRequestConfig) => (await api.get<T>(url, config)).data,
  post: async <T>(url: string, body?: unknown, config?: AxiosRequestConfig) =>
    (await api.post<T>(url, body, config)).data,
  put: async <T>(url: string, body?: unknown, config?: AxiosRequestConfig) =>
    (await api.put<T>(url, body, config)).data,
  patch: async <T>(url: string, body?: unknown, config?: AxiosRequestConfig) =>
    (await api.patch<T>(url, body, config)).data,
  del: async <T>(url: string, config?: AxiosRequestConfig) => (await api.delete<T>(url, config)).data,
};
