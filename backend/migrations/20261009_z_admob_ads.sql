CREATE TABLE IF NOT EXISTS admob_settings (
    environment TEXT PRIMARY KEY CHECK (environment IN ('dev', 'beta', 'prod')),
    rewarded_enabled BOOLEAN NOT NULL DEFAULT false,
    banner_enabled BOOLEAN NOT NULL DEFAULT false,
    interstitial_enabled BOOLEAN NOT NULL DEFAULT false,
    show_to_subscribers BOOLEAN NOT NULL DEFAULT false,
    reward_credits INTEGER NOT NULL DEFAULT 1 CHECK (reward_credits BETWEEN 1 AND 1000),
    daily_reward_limit INTEGER NOT NULL DEFAULT 5 CHECK (daily_reward_limit BETWEEN 0 AND 100),
    android_rewarded_unit_id TEXT NOT NULL DEFAULT '',
    ios_rewarded_unit_id TEXT NOT NULL DEFAULT '',
    android_banner_unit_id TEXT NOT NULL DEFAULT '',
    ios_banner_unit_id TEXT NOT NULL DEFAULT '',
    android_interstitial_unit_id TEXT NOT NULL DEFAULT '',
    ios_interstitial_unit_id TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO admob_settings (environment) VALUES ('prod') ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS admob_reward_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    environment TEXT NOT NULL,
    ad_unit_id TEXT NOT NULL,
    credits INTEGER NOT NULL CHECK (credits > 0),
    created_at TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    consumed_at TIMESTAMP,
    transaction_id TEXT UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_admob_reward_sessions_user
    ON admob_reward_sessions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS admob_reward_events (
    transaction_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES admob_reward_sessions(id),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    environment TEXT NOT NULL,
    credits INTEGER NOT NULL CHECK (credits > 0),
    created_at TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')
);

CREATE INDEX IF NOT EXISTS idx_admob_reward_events_user_day
    ON admob_reward_events(user_id, created_at DESC);
