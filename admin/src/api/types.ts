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

export type StorageProvider = "postgres" | "r2" | "cos";

export interface StorageProviderConfig {
  enabled: boolean;
  endpoint: string;
  bucket: string;
  region: string;
  access_key_configured: boolean;
  secret_key_configured: boolean;
}

export interface StorageConfig {
  environment: Environment;
  active_provider: StorageProvider;
  r2: StorageProviderConfig;
  cos: StorageProviderConfig;
}

export interface StorageProviderInput {
  enabled: boolean;
  endpoint: string;
  bucket: string;
  region: string;
  access_key: string;
  secret_key: string;
}

export interface StorageConfigInput {
  active_provider: StorageProvider;
  r2: StorageProviderInput;
  cos: StorageProviderInput;
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

export type UserBehaviorCategory = "navigation" | "auth" | "onboarding" | "chat" | "companion" | "billing" | "life" | "profile" | "updates" | "system" | "general";

export interface UserBehaviorEvent {
  id: string;
  event_name: string;
  category: UserBehaviorCategory;
  source: "app" | "system";
  properties: Record<string, unknown>;
  platform: string;
  app_version: string;
  session_id: string;
  occurred_at: string;
}

export interface UserBehaviorTimeline {
  items: UserBehaviorEvent[];
  total: number;
  limit: number;
  offset: number;
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

export interface CreditProduct {
  key: string;
  category: "gift" | "photo" | "voice" | "date" | "keepsake" | "outfit" | "call" | "pet";
  name_key: string;
  description_key: string;
  emoji: string;
  coins: number;
  enabled: boolean;
  sort_order: number;
  metadata: Record<string, unknown>;
}

export interface AIPetBreed {
  id: string;
  environment: Environment;
  name: string;
  species: string;
  personality: string;
  description: string;
  avatar_url: string;
  sort_order: number;
  enabled: boolean;
  subscription_plan_ids: string[];
}

export type AIPetBreedInput = Omit<AIPetBreed, "id">;

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

export type MobilePlatform = "ios" | "android";
export type LocalizedCopy = Record<string, string>;

export interface OnboardingContentPage {
  id: string;
  image_url: string;
  icon: "chat" | "life" | "infinity" | "memory" | string;
  title: LocalizedCopy;
  body: LocalizedCopy;
}

export interface OnboardingConfig {
  environment: Environment;
  platform: MobilePlatform;
  enabled: boolean;
  revision: number;
  pages: OnboardingContentPage[];
  updated_by: string;
  updated_at: string;
}

export interface WhatsNewContentPage extends OnboardingContentPage {
  cta_label: LocalizedCopy;
  cta_action: "next" | "close" | "route" | "url" | "";
  cta_value: string;
}

export interface WhatsNewCampaign {
  id: string;
  name: string;
  environment: Environment;
  platform: MobilePlatform;
  min_app_version: string;
  enabled: boolean;
  starts_at: string | null;
  ends_at: string | null;
  pages: WhatsNewContentPage[];
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export interface SocialMediaLinksConfig {
  environment: Environment;
  social_instagram_url: string;
  social_tiktok_url: string;
  social_x_url: string;
  social_discord_url: string;
  updated_by: string;
  updated_at: string;
}

export type LegalDocumentType = "privacy" | "terms";

export interface LegalDocument {
  id: string;
  environment: Environment;
  document_type: LegalDocumentType;
  version: string;
  title: string;
  summary: string;
  content: string;
  is_effective: boolean;
  published_at: string | null;
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export type LegalDocumentInput = Pick<LegalDocument,
  "environment" | "document_type" | "version" | "title" | "summary" | "content">;

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
  capabilities: Array<"text" | "image" | "audio" | "video">;
  configured_scenarios: AIModelScenario[];
  subscription_plan_ids: string[];
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export interface AIModelTestResult {
  scenario: AIModelScenario;
  success: boolean;
  error?: string;
}

export type AIModelScenario =
  | "text_chat"
  | "text_life_plan"
  | "text_proactive"
  | "text_character_profile"
  | "text_story_chapter"
  | "text_storyboard"
  | "image_life_photo"
  | "image_requested_photo"
  | "image_storyboard_sheet"
  | "audio_transcription"
  | "audio_speech"
  | "video_life_clip"
  | "video_realtime_avatar";

export interface AIModelCreateInput {
  provider_id: string;
  model_name: string;
  display_name: string;
  scenarios: AIModelScenario[];
  subscription_plan_ids: string[];
  enabled: boolean;
}

export interface AIModelTestInput {
  provider_id: string;
  model_name: string;
  scenarios: AIModelScenario[];
  transcription_file?: File | null;
}

export interface AIModelTestResponse {
  results: AIModelTestResult[];
}

export interface AIModelInput {
  provider_id: string;
  model_name: string;
  display_name: string;
  capabilities: Array<"text" | "image" | "audio" | "video">;
  subscription_plan_ids: string[];
  enabled: boolean;
}

export interface AgentSettings {
  chat_model_id: string | null;
  life_model_id: string | null;
  proactive_model_id: string | null;
	image_model_id: string | null;
	transcription_model_id: string | null;
	speech_model_id: string | null;
  daily_event_min: number;
  daily_event_max: number;
  daily_proactive_limit: number;
	daily_life_photo_limit: number;
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
  subscription_plans: BillingProduct[];
  settings: AgentSettings;
  portraits: CompanionPortrait[];
}

export type MediaModelType = "text" | "image" | "audio" | "video";

export interface MediaModelRoute {
  route_key: "text_chat" | "text_life_plan" | "text_proactive" | "text_character_profile" | "text_story_chapter" | "text_storyboard" | "image_life_photo" | "image_requested_photo" | "image_storyboard_sheet" | "audio_transcription" | "audio_speech" | "video_life_clip" | "video_realtime_avatar";
  media_type: MediaModelType;
  enabled: boolean;
  primary_model_id: string | null;
  fallback_model_ids: string[];
}

export interface MediaModelRoutesResponse {
  routes: MediaModelRoute[];
  models: AIModel[];
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
  voice_enabled: boolean;
  voice_config: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface AdminCompanionInput extends Omit<AdminCompanion, "id" | "user_email" | "created_at" | "updated_at"> {}

export interface ManagedCompanionListItem {
  id: string;
  user_id: string;
  user_email: string;
  environment: Environment;
  name: string;
  gender: string;
  city: string;
  occupation: string;
  relationship_stage: string;
  active: boolean;
  proactive_enabled: boolean;
  voice_enabled: boolean;
  portrait_url: string;
  conversations: number;
  messages: number;
  created_at: string;
  updated_at: string;
}

export interface ManagedCompanionDetail extends AdminCompanion {
  environment: Environment;
  portrait_url: string;
  model_name: string;
  creation_source: string;
  life_enabled: boolean;
  friendship_active: boolean;
  subscription_paused_at: string | null;
  conversations: number;
  messages: number;
  memories: number;
  life_events: number;
  state: { mood: number; energy: number; stress: number; social_energy: number };
  relationship: { intimacy: number; trust: number; familiarity: number; enthusiasm: number };
}

export interface ManagedCompanionList {
  items: ManagedCompanionListItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface AdminConversation {
  id: string;
  user_id: string;
  companion_id: string;
  message_count: number;
  last_message: string;
  last_message_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface AdminMessage {
  id: string;
  conversation_id: string;
  sender_type: "user" | "assistant" | "companion";
  message_type: string;
  content: string;
  media_url: string;
  payload: Record<string, unknown>;
  source: string;
  life_event_id: string;
  delivery_status: string;
  created_at: string;
}

export interface StoryConfig {
  environment: Environment;
  free_chapter_limit: number;
  custom_background_limit: number;
  storyboard_unlock_chapters: number;
  chapter_coins: number;
  storyboard_coins: number;
}

export interface StoryBackground {
  id: string;
  environment: Environment;
  title: string;
  cover_url: string;
  synopsis: string;
  world_setting: string;
  opening: string;
  genre: string;
  character_constraints: string;
  story_goal: string;
  sort_order: number;
  enabled: boolean;
}

export type StoryBackgroundInput = Omit<StoryBackground, "id">;
