/** Response shapes for the Vita API endpoints the dashboard consumes. */

/** `GET /v1/auth/admin/login` — the bearer token plus the signed-in role. */
export interface AdminLoginResult {
  user_id: string;
  token: string;
  role: string;
}

/** `GET /v1/me` — the account behind the bearer token. */
export interface Profile {
  user_id: string;
  email: string;
  role: string; // "admin" | "user"
  timezone: string;
  created_at: string;
}

/** `GET /v1/health` */
export interface HealthResponse {
  status: string;
  version: string;
}

/** `GET /v1/admin/stats` — live counts for the dashboard tiles. */
export interface AdminStats {
  total_users: number;
  admin_users: number;
  new_users_7d: number;
  total_companions: number;
  new_companions_7d: number;
  total_conversations: number;
  new_conversations_7d: number;
  total_messages: number;
  new_messages_7d: number;
  total_memories: number;
  total_life_events: number;
  today_life_events: number;
  generated_at: string;
}

/** Deployment environments an account can be flagged with. */
export type Environment = "dev" | "beta" | "prod";

export const ENVIRONMENTS: Environment[] = ["dev", "beta", "prod"];

/** `GET /v1/admin/environment` — the deployment this API instance runs in. */
export interface AdminEnvironment {
  environment: Environment;
}

/** A user account as seen by the admin console (`/v1/admin/users`). */
export interface AdminUser {
  id: string;
  email: string;
  role: string; // "user" | "admin"
  timezone: string;
  /** Environment the account registered on (dev | beta | prod). */
  environment: Environment;
  banned: boolean;
  created_at: string;
  updated_at: string;
}

/** `GET /v1/admin/users/:id` — detail adds per-account usage counts. */
export interface AdminUserDetail extends AdminUser {
  companions: number;
  conversations: number;
  messages: number;
  memories: number;
}

/** `GET /v1/admin/users` — paginated list response. */
export interface AdminUserList {
  items: AdminUser[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

/** Query params for the paginated user list. */
export interface AdminUserListParams {
  page?: number;
  page_size?: number;
  q?: string;
  role?: string;
  status?: "active" | "banned";
  environment?: Environment;
}

/** Create/update payload for a user. */
export interface AdminUserInput {
  email?: string;
  password?: string;
  role?: string;
  timezone?: string;
  environment?: Environment;
}

export type BillingPlatform = "ios" | "android" | "web";

export interface BillingProduct {
  id: string;
  key: string;
  name: string;
  environment: Environment;
  platform: BillingPlatform;
  coins: number;
  price_usd: number;
  period?: "week" | "month" | "year";
  product_id: string;
  popular?: boolean;
  enabled: boolean;
  sort_order: number;
  created_at?: string;
  updated_at?: string;
}

export interface BillingPurchase {
  id: string;
  transaction_id: string;
  user_id: string;
  user_email: string;
  kind: "subscription" | "coin_pack";
  provider: string;
  platform: BillingPlatform | "system";
  environment: Environment;
  product_id: string;
  amount_minor: number | null;
  currency: string;
  credits: number;
  status: string;
  purchased_at: string;
}

export interface CreditLedgerEntry {
  id: string;
  user_id: string;
  user_email: string;
  amount: number;
  balance_after: number;
  kind: string;
  description: string;
  platform: BillingPlatform | "system";
  environment: Environment;
  created_at: string;
}

export interface BillingList<T> {
  items: T[];
}

export interface BillingPagedList<T> extends BillingList<T> {
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface AdminGrantOperation {
  id: string;
  operator_user_id: string | null;
  operator_email: string;
  target_user_id: string;
  target_email: string;
  operation_type: "coins" | "subscription";
  coins: number;
  plan_id: string | null;
  plan_name: string;
  subscription_id: string | null;
  expires_at: string | null;
  note: string;
  platform: BillingPlatform | "system";
  environment: Environment;
  created_at: string;
}

export interface AdminGrantResult {
  id: string;
  coins: number;
  balance: number;
  subscription_id?: string;
  plan_name?: string;
  expires_at?: string;
}

export interface InvitationSettings {
  reward_basis_points: number;
  reward_percent: number;
  invited_users: number;
  rewarded_coins: number;
}

export type AIProviderKind = "openai" | "anthropic";

export interface AIProvider {
  id: string;
  name: string;
  kind: AIProviderKind;
  base_url: string;
  api_key_configured: boolean;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export interface AIProviderInput {
  name: string;
  kind: AIProviderKind;
  base_url: string;
  /** Write-only. Empty on update keeps the existing key. */
  api_key?: string;
  enabled: boolean;
}

export interface AIModel {
  id: string;
  provider_id: string;
  provider_name: string;
  model_name: string;
  display_name: string;
  capabilities: Array<"text" | "image" | "audio">;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export interface AIModelInput {
  provider_id: string;
  model_name: string;
  display_name: string;
  capabilities: Array<"text" | "image" | "audio">;
  enabled: boolean;
}

export interface AgentSettings {
  chat_model_id: string | null;
  life_model_id: string | null;
  proactive_model_id: string | null;
  daily_event_min: number;
  daily_event_max: number;
  daily_proactive_limit: number;
  quiet_hours_start: number;
  quiet_hours_end: number;
  free_default_chat_hours: number;
}

export interface CompanionPortrait {
  id: string;
  name: string;
  image_url: string;
  gender: string;
  personality_tags: string[];
  is_default: boolean;
  enabled: boolean;
  sort_order: number;
}

export interface AgentConfig {
  providers: AIProvider[];
  models: AIModel[];
  settings: AgentSettings;
  portraits: CompanionPortrait[];
}

export interface AdminCompanion {
  id: string;
  user_id: string;
  user_email: string;
  name: string;
  gender: string;
  persona: string;
  city: string;
  occupation: string;
  interests: string;
  relationship_stage: string;
  personality_tags: string[];
  speaking_style: string;
  likes: string;
  dislikes: string;
  life_habits: string;
  life_goal: string;
  backstory: string;
  model_id: string | null;
  portrait_id: string | null;
  proactive_enabled: boolean;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface AdminCompanionInput extends Omit<AdminCompanion, "id" | "user_email" | "created_at" | "updated_at"> {}
