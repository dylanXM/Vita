import { http } from "./client";
import type { AdminLoginResult, AdminStats, HealthResponse, Profile } from "./types";

/** Admin sign-in. The API also accepts a 6-digit code for the same accounts. */
export const authApi = {
  login: (email: string, password: string) =>
    http.post<AdminLoginResult>("/auth/admin/login", { email, password }),
  me: (signal?: AbortSignal) => http.get<Profile>("/me", { signal }),
};

/** Live counts behind the dashboard tiles. */
export const statsApi = {
  get: (signal?: AbortSignal) => http.get<AdminStats>("/admin/stats", { signal }),
};

export const healthApi = {
  get: (signal?: AbortSignal) => http.get<HealthResponse>("/health", { signal }),
};
