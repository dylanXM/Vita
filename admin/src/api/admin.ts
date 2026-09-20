import { http } from "./client";
import type {
  AdminEnvironment,
  AdminLoginResult,
  AdminStats,
  AdminUser,
  AdminUserDetail,
  AdminUserInput,
  AdminUserList,
  AdminUserListParams,
  HealthResponse,
  Profile,
  AgentConfig,
  AgentSettings,
  AIModel,
  AIModelInput,
  AIProvider,
  AIProviderInput,
  AdminCompanion,
  AdminCompanionInput,
  CompanionPortrait,
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

/** Deployment environment of the API instance (admin-only). */
export const envApi = {
  get: (signal?: AbortSignal) => http.get<AdminEnvironment>("/admin/environment", { signal }),
};

export const healthApi = {
  get: (signal?: AbortSignal) => http.get<HealthResponse>("/health", { signal }),
};

export const agentApi = {
  config: (signal?: AbortSignal) => http.get<AgentConfig>("/admin/agent/config", { signal }),
  saveSettings: (body: AgentSettings) => http.put<AgentSettings>("/admin/agent/settings", body),
  createProvider: (body: AIProviderInput) => http.post<AIProvider>("/admin/agent/providers", body),
  updateProvider: (id: string, body: AIProviderInput) =>
    http.put<AIProvider>(`/admin/agent/providers/${id}`, body),
  removeProvider: (id: string) => http.del<{ message: string }>(`/admin/agent/providers/${id}`),
  createModel: (body: AIModelInput) => http.post<AIModel>("/admin/agent/models", body),
  updateModel: (id: string, body: AIModelInput) =>
    http.put<AIModel>(`/admin/agent/models/${id}`, body),
  removeModel: (id: string) => http.del<{ message: string }>(`/admin/agent/models/${id}`),
  createPortrait: (body: Omit<CompanionPortrait, "id">) =>
    http.post<CompanionPortrait>("/admin/agent/portraits", body),
  updatePortrait: (id: string, body: Omit<CompanionPortrait, "id">) =>
    http.put<CompanionPortrait>(`/admin/agent/portraits/${id}`, body),
  companions: (signal?: AbortSignal) =>
    http.get<{ items: AdminCompanion[] }>("/admin/agent/companions", { signal }),
  createCompanion: (body: AdminCompanionInput) =>
    http.post<{ id: string }>("/admin/agent/companions", body),
  updateCompanion: (id: string, body: AdminCompanionInput) =>
    http.put<{ id: string }>(`/admin/agent/companions/${id}`, body),
};
