import { http } from "./client";
import type {
  AdminLoginResult,
  AdminStats,
  AdminUser,
  AdminUserDetail,
  AdminUserInput,
  AdminUserList,
  AdminUserListParams,
  HealthResponse,
  Profile,
} from "./types";

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

/** Admin user management — every call is admin-only on the server. */
export const usersApi = {
  list: (params: AdminUserListParams, signal?: AbortSignal) =>
    http.get<AdminUserList>("/admin/users", { params, signal }),
  get: (id: string, signal?: AbortSignal) =>
    http.get<AdminUserDetail>(`/admin/users/${id}`, { signal }),
  create: (body: AdminUserInput) => http.post<AdminUser>("/admin/users", body),
  update: (id: string, body: AdminUserInput) => http.put<AdminUser>(`/admin/users/${id}`, body),
  remove: (id: string) => http.del<{ message: string }>(`/admin/users/${id}`),
  ban: (id: string) => http.post<AdminUser>(`/admin/users/${id}/ban`),
  unban: (id: string) => http.post<AdminUser>(`/admin/users/${id}/unban`),
};

export const healthApi = {
  get: (signal?: AbortSignal) => http.get<HealthResponse>("/health", { signal }),
};
