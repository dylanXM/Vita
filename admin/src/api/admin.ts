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
  AIModelCreateInput,
  AIModelInput,
  AIModelTestInput,
  AIModelTestResponse,
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
  ManagedCompanionDetail,
  ManagedCompanionList,
  AdminConversation,
  AdminMessage,
  UserBehaviorCategory,
  UserBehaviorTimeline,
  OnboardingConfig,
  WhatsNewCampaign,
  MobilePlatform,
  SocialMediaLinksConfig,
  CreditProduct,
  MediaModelRoute,
  MediaModelRoutesResponse,
  LegalDocument,
  LegalDocumentInput,
  LegalDocumentType,
  AIPetBreed,
  AIPetBreedInput,
  StoryConfig,
  StoryBackground,
  StoryBackgroundInput,
  StorageConfig,
  StorageConfigInput,
  StorageProvider,
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
  timeline: (id: string, params: { category?: UserBehaviorCategory; limit?: number; offset?: number }, signal?: AbortSignal) =>
    http.get<UserBehaviorTimeline>(`/admin/users/${id}/timeline`, { params, signal }),
};

/** Deployment environment of the API instance (admin-only). */
export const envApi = {
  get: (signal?: AbortSignal) => http.get<AdminEnvironment>("/admin/environment", { signal }),
};

export const storageApi = {
  get: (environment: Environment, signal?: AbortSignal) =>
    http.get<StorageConfig>("/admin/storage-config", { params: { environment }, signal }),
  save: (environment: Environment, body: StorageConfigInput) =>
    http.put<StorageConfig>("/admin/storage-config", body, { params: { environment } }),
  test: (environment: Environment, provider: Exclude<StorageProvider, "postgres">) =>
    http.post<{ provider: string; success: boolean }>("/admin/storage-config/test", undefined, { params: { environment, provider } }),
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

export const creditProductsApi = {
  list: (environment: Environment, signal?: AbortSignal) =>
    http.get<BillingList<CreditProduct>>("/admin/credit-products", { params: { environment }, signal }),
  update: (environment: Environment, key: string, body: Pick<CreditProduct, "coins" | "enabled" | "sort_order">) =>
    http.put<BillingList<CreditProduct>>(`/admin/credit-products/${key}`, body, { params: { environment } }),
};

export const invitationApi = {
  settings: (signal?: AbortSignal) =>
    http.get<InvitationSettings>("/admin/invitation-settings", { signal }),
  saveSettings: (rewardPercent: number) =>
    http.put<InvitationSettings>("/admin/invitation-settings", { reward_percent: rewardPercent }),
};

export const onboardingApi = {
  get: (environment: Environment, platform: MobilePlatform, signal?: AbortSignal) =>
    http.get<OnboardingConfig>("/admin/onboarding", { params: { environment, platform }, signal }),
  save: (environment: Environment, platform: MobilePlatform, body: Pick<OnboardingConfig, "enabled" | "revision" | "pages">) =>
    http.put<OnboardingConfig>("/admin/onboarding", body, { params: { environment, platform } }),
};

export const whatsNewApi = {
  list: (environment: Environment, platform: MobilePlatform, signal?: AbortSignal) =>
    http.get<{ items: WhatsNewCampaign[] }>("/admin/whats-new", { params: { environment, platform }, signal }),
  create: (body: Omit<WhatsNewCampaign, "id" | "updated_by" | "created_at" | "updated_at">) =>
    http.post<WhatsNewCampaign>("/admin/whats-new", body),
  update: (id: string, body: Omit<WhatsNewCampaign, "id" | "updated_by" | "created_at" | "updated_at">) =>
    http.put<WhatsNewCampaign>(`/admin/whats-new/${id}`, body),
  remove: (id: string) => http.del<{ message: string }>(`/admin/whats-new/${id}`),
};

export const socialLinksApi = {
  get: (environment: Environment, signal?: AbortSignal) =>
    http.get<SocialMediaLinksConfig>("/admin/social-links", { params: { environment }, signal }),
  save: (environment: Environment, body: Pick<SocialMediaLinksConfig,
    "social_instagram_url" | "social_tiktok_url" | "social_x_url" | "social_discord_url">) =>
    http.put<SocialMediaLinksConfig>("/admin/social-links", body, { params: { environment } }),
};

export const aiPetBreedsApi = {
  list: (environment: Environment, signal?: AbortSignal) =>
    http.get<BillingList<AIPetBreed>>("/admin/ai-pet-breeds", { params: { environment }, signal }),
  create: (body: AIPetBreedInput) => http.post<AIPetBreed>("/admin/ai-pet-breeds", body),
  update: (id: string, body: AIPetBreedInput) =>
    http.put<AIPetBreed>(`/admin/ai-pet-breeds/${id}`, body),
};

export const storiesApi = {
  config: (environment: Environment, signal?: AbortSignal) =>
    http.get<StoryConfig>("/admin/story-config", { params: { environment }, signal }),
  saveConfig: (body: StoryConfig) => http.put<StoryConfig>("/admin/story-config", body),
  backgrounds: (environment: Environment, signal?: AbortSignal) =>
    http.get<{ items: StoryBackground[] }>("/admin/story-backgrounds", { params: { environment }, signal }),
  createBackground: (body: StoryBackgroundInput) => http.post<{ id: string }>("/admin/story-backgrounds", body),
  updateBackground: (id: string, body: StoryBackgroundInput) => http.put<{ id: string }>(`/admin/story-backgrounds/${id}`, body),
  removeBackground: (id: string) => http.del<{ message: string }>(`/admin/story-backgrounds/${id}`),
};

export const legalDocumentsApi = {
  list: (environment: Environment, documentType: LegalDocumentType, signal?: AbortSignal) =>
    http.get<{ items: LegalDocument[] }>("/admin/legal-documents", {
      params: { environment, document_type: documentType }, signal,
    }),
  create: (body: LegalDocumentInput) =>
    http.post<LegalDocument>("/admin/legal-documents", body),
  update: (id: string, body: LegalDocumentInput) =>
    http.put<LegalDocument>(`/admin/legal-documents/${id}`, body),
  activate: (id: string) =>
    http.post<LegalDocument>(`/admin/legal-documents/${id}/activate`),
  remove: (id: string) =>
    http.del<{ message: string }>(`/admin/legal-documents/${id}`),
};

export const agentApi = {
  config: (env?: string, signal?: AbortSignal) =>
    http.get<AgentConfig>("/admin/agent/config", { signal, params: env ? { environment: env } : undefined }),
  saveSettings: (body: AgentSettings) => http.put<AgentSettings>("/admin/agent/settings", body),
  createProvider: (body: AIProviderInput) => http.post<AIProvider>("/admin/agent/providers", body),
  updateProvider: (id: string, body: AIProviderInput) =>
    http.put<AIProvider>(`/admin/agent/providers/${id}`, body),
  removeProvider: (id: string) => http.del<{ message: string }>(`/admin/agent/providers/${id}`),
  createModel: (body: AIModelCreateInput) => http.post<AIModel>("/admin/agent/models", body),
  testModel: (body: AIModelTestInput) => {
    const form = new FormData();
    if (body.provider_id) form.set("provider_id", body.provider_id);
    form.set("model_name", body.model_name);
    form.set("scenarios", JSON.stringify(body.scenarios));
    if (body.kind) form.set("kind", body.kind);
    if (body.base_url) form.set("base_url", body.base_url);
    if (body.api_key) form.set("api_key", body.api_key);
    if (body.transcription_file) form.set("transcription_file", body.transcription_file);
    return http.post<AIModelTestResponse>("/admin/agent/models/test", form, { timeout: 360_000 });
  },
  updateModel: (id: string, body: AIModelInput) =>
    http.put<AIModel>(`/admin/agent/models/${id}`, body),
  removeModel: (id: string) => http.del<{ message: string }>(`/admin/agent/models/${id}`),
  testProviderConnection: (body: { kind: string; base_url: string; api_key?: string; provider_id?: string }) =>
    http.post<{ success: boolean; message: string; models?: string[]; raw?: string }>("/admin/agent/providers/test-connection", body, { timeout: 60_000 }),
  mediaRoutes: (signal?: AbortSignal) =>
    http.get<MediaModelRoutesResponse>("/admin/agent/media-routes", { signal }),
  saveMediaRoutes: (routes: MediaModelRoute[]) =>
    http.put<MediaModelRoutesResponse>("/admin/agent/media-routes", { routes }),
  createPortrait: (body: Omit<CompanionPortrait, "id">) =>
    http.post<CompanionPortrait>("/admin/agent/portraits", body),
  updatePortrait: (id: string, body: Omit<CompanionPortrait, "id">) =>
    http.put<CompanionPortrait>(`/admin/agent/portraits/${id}`, body),
  companions: (env?: string, signal?: AbortSignal) =>
    http.get<{ items: AdminCompanion[] }>("/admin/agent/companions", { signal, params: env ? { environment: env } : undefined }),
  createCompanion: (body: AdminCompanionInput) =>
    http.post<{ id: string }>("/admin/agent/companions", body),
  updateCompanion: (id: string, body: AdminCompanionInput) =>
    http.put<{ id: string }>(`/admin/agent/companions/${id}`, body),
};


export interface CompanionFilters {
  page?: number;
  page_size?: number;
  q?: string;
  user_id?: string;
  status?: "active" | "inactive";
  environment?: Environment;
}

export const companionsApi = {
  list: (params: CompanionFilters, signal?: AbortSignal) =>
    http.get<ManagedCompanionList>("/admin/companions", { params, signal }),
  get: (id: string, signal?: AbortSignal) =>
    http.get<ManagedCompanionDetail>(`/admin/companions/${id}`, { signal }),
  update: (id: string, body: AdminCompanionInput) =>
    http.put<{ id: string }>(`/admin/companions/${id}`, body),
  remove: (id: string) => http.del<{ message: string }>(`/admin/companions/${id}`),
  conversations: (id: string, signal?: AbortSignal) =>
    http.get<{ items: AdminConversation[] }>(`/admin/companions/${id}/conversations`, { signal }),
  messages: (id: string, conversationID: string, page = 1, signal?: AbortSignal) =>
    http.get<BillingPagedList<AdminMessage>>(
      `/admin/companions/${id}/conversations/${conversationID}/messages`,
      { params: { page, page_size: 50 }, signal },
    ),
};
