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
  AdminGrantOperation,
  AdminGrantResult,
  InvitationSettings,
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
  BillingPlatform,
  BillingProduct,
  BillingPurchase,
  CreditLedgerEntry,
  BillingList,
  BillingPagedList,
  Environment,
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
  grantOperations: (id: string, signal?: AbortSignal) =>
    http.get<BillingList<AdminGrantOperation>>(`/admin/users/${id}/grant-operations`, { signal }),
  grantCoins: (id: string, body: { coins: number; note: string }) =>
    http.post<AdminGrantResult>(`/admin/users/${id}/grant-coins`, body),
  grantSubscription: (id: string, body: { plan_id: string; ends_at: string; note: string }) =>
    http.post<AdminGrantResult>(`/admin/users/${id}/grant-subscription`, body),
};

/** Deployment environment of the API instance (admin-only). */
export const envApi = {
  get: (signal?: AbortSignal) => http.get<AdminEnvironment>("/admin/environment", { signal }),
};

export const healthApi = {
  get: (signal?: AbortSignal) => http.get<HealthResponse>("/health", { signal }),
};

export interface BillingFilters {
  environment: Environment;
  platform?: BillingPlatform | "system";
  page?: number;
  page_size?: number;
}

export const subscriptionPlansApi = {
  list: (params: Pick<BillingFilters, "environment" | "platform">, signal?: AbortSignal) =>
    http.get<BillingList<BillingProduct>>("/admin/subscription-plans", { params, signal }),
  create: (body: Omit<BillingProduct, "id">) =>
    http.post<BillingProduct>("/admin/subscription-plans", body),
  update: (id: string, body: Omit<BillingProduct, "id">) =>
    http.put<BillingProduct>(`/admin/subscription-plans/${id}`, body),
  remove: (id: string) => http.del<{ message: string }>(`/admin/subscription-plans/${id}`),
};

export const coinPacksApi = {
  list: (params: Pick<BillingFilters, "environment" | "platform">, signal?: AbortSignal) =>
    http.get<BillingList<BillingProduct>>("/admin/coin-packs", { params, signal }),
  create: (body: Omit<BillingProduct, "id">) => http.post<BillingProduct>("/admin/coin-packs", body),
  update: (id: string, body: Omit<BillingProduct, "id">) =>
    http.put<BillingProduct>(`/admin/coin-packs/${id}`, body),
  remove: (id: string) => http.del<{ message: string }>(`/admin/coin-packs/${id}`),
};

export const purchasesApi = {
  list: (params: BillingFilters, signal?: AbortSignal) =>
    http.get<BillingPagedList<BillingPurchase>>("/admin/purchases", { params, signal }),
};

export const creditLedgerApi = {
  list: (params: BillingFilters, signal?: AbortSignal) =>
    http.get<BillingPagedList<CreditLedgerEntry>>("/admin/credit-ledger", { params, signal }),
};

export const invitationApi = {
  settings: (signal?: AbortSignal) =>
    http.get<InvitationSettings>("/admin/invitation-settings", { signal }),
  saveSettings: (rewardPercent: number) =>
    http.put<InvitationSettings>("/admin/invitation-settings", { reward_percent: rewardPercent }),
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
