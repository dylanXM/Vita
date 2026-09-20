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
}

export interface CompanionPortrait {
  id: string;
  name: string;
  image_url: string;
  gender: string;
  personality_tags: string[];
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
