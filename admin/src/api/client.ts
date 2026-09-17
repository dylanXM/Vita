import axios, { type AxiosRequestConfig } from "axios";
import { getLocale } from "@/i18n";

/** localStorage key for the admin access token. */
export const TOKEN_KEY = "vita_admin_token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
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

// A 401 on an authenticated call means the session is dead: drop the token and
// bounce to login, preserving where we were so we can return after re-auth.
// Failed sign-ins also answer 401, so this is skipped while already on /login.
api.interceptors.response.use(
  (res) => res,
  (error) => {
    if (error?.response?.status === 401) {
      setToken(null);
      const here = window.location.pathname + window.location.search;
      if (!window.location.pathname.startsWith("/login")) {
        window.location.assign(`/login?redirect=${encodeURIComponent(here)}`);
      }
    }
    return Promise.reject(error);
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
