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
