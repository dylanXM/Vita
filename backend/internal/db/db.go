package db

import (
	"database/sql"
	"fmt"
	_ "github.com/lib/pq"
	"vita/internal/config"
)

var _db *sql.DB

func Open(cfg *config.Config) (*sql.DB, error) {
	db, err := sql.Open("postgres", cfg.DBDSN)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)

	if cfg.AutoMigrate {
		if err := Migrate(db); err != nil {
			return nil, fmt.Errorf("migration failed: %w", err)
		}
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("database ping failed: %w", err)
	}

	_db = db
	fmt.Println("database connected successfully")
	return db, nil
}

func Close() {
	if _db != nil {
		_db.Close()
	}
}

func Get() *sql.DB {
	return _db
}

// Migrate applies the idempotent schema required by the current backend.
// Production runs this explicitly through cmd/migrate before the API starts.
func Migrate(db *sql.DB) error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS roles (
			id TEXT PRIMARY KEY,
			name TEXT UNIQUE NOT NULL,
			description TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			email TEXT UNIQUE NOT NULL,
			role_id TEXT NOT NULL DEFAULT 'user',
			password_hash TEXT NOT NULL DEFAULT '',
			timezone TEXT DEFAULT 'UTC',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS verification_codes (
			id TEXT PRIMARY KEY,
			email TEXT NOT NULL,
			code TEXT NOT NULL,
			purpose TEXT NOT NULL DEFAULT 'login',
			expires_at TIMESTAMP NOT NULL,
			used BOOLEAN DEFAULT false,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_verification_codes_email ON verification_codes(email)`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS banned BOOLEAN NOT NULL DEFAULT false`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS credits_balance INTEGER NOT NULL DEFAULT 0`,
		// Environment the account registered on (dev | beta | prod). Beta and
		// prod share one database, so the flag lives on the row, not per-server.
		// Existing rows predate the flag — they are live production accounts.
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'prod'`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS legal_accepted_at TIMESTAMP`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_policy_version TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_version TEXT NOT NULL DEFAULT ''`,
		`CREATE TABLE IF NOT EXISTS legal_documents (
			id TEXT PRIMARY KEY,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			document_type TEXT NOT NULL CHECK (document_type IN ('privacy', 'terms')),
			version TEXT NOT NULL,
			title TEXT NOT NULL,
			summary TEXT NOT NULL DEFAULT '',
			content TEXT NOT NULL,
			is_effective BOOLEAN NOT NULL DEFAULT false,
			published_at TIMESTAMP,
			updated_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(environment, document_type, version)
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_legal_documents_effective
			ON legal_documents(environment, document_type) WHERE is_effective`,
		`CREATE INDEX IF NOT EXISTS idx_legal_documents_list
			ON legal_documents(environment, document_type, updated_at DESC)`,
		`INSERT INTO legal_documents(id,environment,document_type,version,title,summary,content,is_effective,published_at,updated_by)
		SELECT 'default-' || environment || '-privacy', environment, 'privacy', '2026-09-20', 'Privacy Policy',
		'This policy explains what Vita collects, why it is used, and the choices you have.',
		$$1. Information we collect
We process your email address, encrypted authentication credentials, profile settings, companion profiles, messages, voice recordings, uploaded media, memories, purchase status and necessary usage events.

2. How we use information
We use this information to create and secure your account, deliver conversations and media, maintain companion continuity, provide purchases and support, prevent abuse, diagnose faults and improve Vita. We do not sell personal information.

3. AI and service providers
Requests and media may be sent to configured AI providers to generate text, images, speech or transcriptions. Payments and delivery services process only the data needed to provide their service.

4. Storage and security
Information is retained only while needed for the service, legal obligations, fraud prevention and dispute handling. We use access controls and encryption in transit.

5. Your choices and rights
You can correct account information, manage device permissions, sign out or permanently delete your account from Settings. Store subscriptions must be cancelled separately.

6. Children and contact
Vita is not intended for children below the minimum age required in their country. Privacy questions can be sent to support@vita.app.$$,
		true,CURRENT_TIMESTAMP,'system'
		FROM (VALUES ('dev'),('beta'),('prod')) AS environments(environment)
		ON CONFLICT(environment,document_type,version) DO NOTHING`,
		`INSERT INTO legal_documents(id,environment,document_type,version,title,summary,content,is_effective,published_at,updated_by)
		SELECT 'default-' || environment || '-terms', environment, 'terms', '2026-09-20', 'Terms of Service',
		'These terms govern your use of Vita and explain the rules of the service.',
		$$1. Accepting these terms
By creating a Vita account, you confirm that you have read and accepted these Terms and the Privacy Policy. If you do not agree, do not register or use the service.

2. The service
Vita provides fictional AI companion conversations, generated life events, memories and optional paid digital experiences. AI output may be inaccurate and must not be treated as professional, medical, legal, financial or emergency advice.

3. Your account and content
You must protect your credentials and remain responsible for activity under your account. You retain rights in submitted content and grant Vita the limited permission needed to process it and provide the service.

4. Acceptable use
Do not use Vita to break the law, harm others, infringe rights, obtain unauthorized access, distribute malware, manipulate purchases or automate abuse.

5. Purchases
Prices and benefits are shown before purchase. Store subscriptions renew and are cancelled under store rules. Consumed digital benefits are not refundable except where required by law or store policy.

6. Availability and contact
Features may change, be suspended or end. You may stop using Vita or delete your account at any time. Questions can be sent to support@vita.app.$$,
		true,CURRENT_TIMESTAMP,'system'
		FROM (VALUES ('dev'),('beta'),('prod')) AS environments(environment)
		ON CONFLICT(environment,document_type,version) DO NOTHING`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_locale TEXT NOT NULL DEFAULT 'en'`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_code TEXT`,
		`UPDATE users SET invite_code=UPPER(SUBSTRING(MD5(id || email) FROM 1 FOR 10)) WHERE invite_code IS NULL OR invite_code=''`,
		`ALTER TABLE users ALTER COLUMN invite_code SET DEFAULT UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT) FROM 1 FOR 10))`,
		`ALTER TABLE users ALTER COLUMN invite_code SET NOT NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_invite_code ON users(invite_code)`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS invited_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL`,
		`CREATE INDEX IF NOT EXISTS idx_users_invited_by ON users(invited_by_user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_users_environment ON users(environment)`,
		`CREATE INDEX IF NOT EXISTS idx_verification_codes_expires ON verification_codes(expires_at)`,
		`CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)`,
		`CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)`,
		`CREATE TABLE IF NOT EXISTS credit_transactions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			amount INTEGER NOT NULL,
			balance_after INTEGER NOT NULL,
			kind TEXT NOT NULL DEFAULT 'grant',
			description TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_credit_transactions_user ON credit_transactions(user_id, created_at DESC)`,
		`ALTER TABLE credit_transactions ADD COLUMN IF NOT EXISTS platform TEXT`,
		`ALTER TABLE credit_transactions ADD COLUMN IF NOT EXISTS environment TEXT`,
		`UPDATE credit_transactions SET platform = 'system' WHERE platform IS NULL`,
		`UPDATE credit_transactions ct SET environment = u.environment FROM users u WHERE ct.user_id = u.id AND ct.environment IS NULL`,
		`ALTER TABLE credit_transactions ALTER COLUMN platform SET DEFAULT 'system'`,
		`ALTER TABLE credit_transactions ALTER COLUMN platform SET NOT NULL`,
		`ALTER TABLE credit_transactions ALTER COLUMN environment SET DEFAULT 'prod'`,
		`ALTER TABLE credit_transactions ALTER COLUMN environment SET NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_credit_transactions_scope ON credit_transactions(environment, platform, created_at DESC)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_transactions_annual_subscription_month
			ON credit_transactions(user_id,description)
			WHERE description LIKE 'annual-subscription-month:%'`,
		`CREATE TABLE IF NOT EXISTS credit_products (
			environment TEXT NOT NULL CHECK (environment IN ('dev','beta','prod')),
			product_key TEXT NOT NULL,
			category TEXT NOT NULL CHECK (category IN ('gift','photo','voice','date','keepsake','outfit','call')),
			name_key TEXT NOT NULL,
			description_key TEXT NOT NULL DEFAULT '',
			emoji TEXT NOT NULL DEFAULT '',
			coins INTEGER NOT NULL CHECK (coins > 0),
			enabled BOOLEAN NOT NULL DEFAULT true,
			sort_order INTEGER NOT NULL DEFAULT 0,
			metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY(environment,product_key)
		)`,
		`INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
		SELECT env,key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::jsonb FROM (VALUES
			('gift_coffee','gift','experience.gift.coffee','experience.gift.coffee.desc','☕',10,true,10,'{"intimacy":1,"enthusiasm":2}'),
			('gift_flowers','gift','experience.gift.flowers','experience.gift.flowers.desc','💐',30,true,20,'{"intimacy":2,"enthusiasm":4}'),
			('gift_cake','gift','experience.gift.cake','experience.gift.cake.desc','🎂',50,true,30,'{"intimacy":3,"enthusiasm":6}'),
			('gift_keepsake','gift','experience.gift.keepsake','experience.gift.keepsake.desc','🎁',100,true,40,'{"intimacy":5,"enthusiasm":8}'),
			('legacy_gift_10','gift','experience.gift.coffee','experience.gift.coffee.desc','☕',10,true,900,'{"intimacy":1,"enthusiasm":2,"hidden_from_catalog":true}'),
			('legacy_gift_50','gift','experience.gift.cake','experience.gift.cake.desc','🎂',50,true,910,'{"intimacy":3,"enthusiasm":6,"hidden_from_catalog":true}'),
			('legacy_gift_100','gift','experience.gift.keepsake','experience.gift.keepsake.desc','🎁',100,true,920,'{"intimacy":5,"enthusiasm":8,"hidden_from_catalog":true}'),
			('life_photo','photo','experience.photo','experience.photo.desc','📷',30,true,10,'{}'),
			('voice_reply','voice','experience.voice','experience.voice.desc','🎙️',10,true,10,'{}'),
			('date_coffee','date','experience.date.coffee','experience.date.coffee.desc','☕',100,true,10,'{"duration_minutes":60,"location":"cafe"}'),
			('date_movie','date','experience.date.movie','experience.date.movie.desc','🎬',150,true,20,'{"duration_minutes":150,"location":"cinema"}'),
			('date_dinner','date','experience.date.dinner','experience.date.dinner.desc','🍽️',200,true,30,'{"duration_minutes":90,"location":"restaurant"}'),
			('memory_card','keepsake','experience.keepsake','experience.keepsake.desc','💌',60,true,10,'{}'),
			('outfit_casual','outfit','experience.outfit.casual','experience.outfit.casual.desc','👕',80,true,10,'{"style":"casual everyday outfit"}'),
			('outfit_evening','outfit','experience.outfit.evening','experience.outfit.evening.desc','✨',150,true,20,'{"style":"elegant evening outfit"}'),
			('outfit_travel','outfit','experience.outfit.travel','experience.outfit.travel.desc','🧳',120,true,30,'{"style":"comfortable travel outfit"}'),
			('voice_call_minute','call','experience.call.voice','experience.call.voice.desc','📞',15,false,10,'{"mode":"voice","seconds":60}'),
			('video_call_minute','call','experience.call.video','experience.call.video.desc','📹',40,false,20,'{"mode":"video","seconds":60}')
		) AS defaults(key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
		CROSS JOIN (VALUES('dev'),('beta'),('prod')) AS environments(env)
		ON CONFLICT(environment,product_key) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS credit_spends (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT,
			product_key TEXT NOT NULL,
			coins INTEGER NOT NULL CHECK (coins > 0),
			status TEXT NOT NULL CHECK (status IN ('reserved','completed','refunded')),
			idempotency_key TEXT NOT NULL,
			reference_type TEXT NOT NULL DEFAULT '',
			reference_id TEXT NOT NULL DEFAULT '',
			metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
			result JSONB NOT NULL DEFAULT '{}'::jsonb,
			failure_reason TEXT NOT NULL DEFAULT '',
			completed_at TIMESTAMP,
			refunded_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(user_id,idempotency_key)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_credit_spends_user ON credit_spends(user_id,created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_credit_spends_status ON credit_spends(status,created_at)`,
		`ALTER TABLE credit_transactions ADD COLUMN IF NOT EXISTS spend_id TEXT REFERENCES credit_spends(id) ON DELETE SET NULL`,
		`CREATE INDEX IF NOT EXISTS idx_credit_transactions_spend ON credit_transactions(spend_id)`,
		`CREATE TABLE IF NOT EXISTS invitation_settings (
			environment TEXT PRIMARY KEY CHECK (environment IN ('dev', 'beta', 'prod')),
			reward_basis_points INTEGER NOT NULL DEFAULT 1000 CHECK (reward_basis_points >= 0 AND reward_basis_points <= 10000),
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`INSERT INTO invitation_settings(environment) VALUES('dev'),('beta'),('prod') ON CONFLICT(environment) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS invitation_rewards (
			id TEXT PRIMARY KEY,
			inviter_user_id TEXT NOT NULL REFERENCES users(id),
			invited_user_id TEXT NOT NULL REFERENCES users(id),
			source_transaction_id TEXT NOT NULL REFERENCES credit_transactions(id),
			reward_transaction_id TEXT NOT NULL REFERENCES credit_transactions(id),
			source_coins INTEGER NOT NULL,
			reward_coins INTEGER NOT NULL,
			reward_basis_points INTEGER NOT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(source_transaction_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_invitation_rewards_inviter ON invitation_rewards(inviter_user_id,created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS subscriptions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			provider TEXT NOT NULL,
			provider_ref TEXT NOT NULL,
			app_user_id TEXT,
			product_id TEXT,
			entitlement TEXT,
			status TEXT NOT NULL DEFAULT 'active',
			current_period_start TIMESTAMP,
			current_period_end TIMESTAMP,
			will_renew BOOLEAN DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_provider_ref ON subscriptions(provider, provider_ref)`,
		`CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id)`,
		`ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS platform TEXT`,
		`ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS environment TEXT`,
		`UPDATE subscriptions SET platform = CASE WHEN provider = 'stripe' THEN 'web' ELSE 'system' END WHERE platform IS NULL`,
		`UPDATE subscriptions s SET environment = u.environment FROM users u WHERE s.user_id = u.id AND s.environment IS NULL`,
		`ALTER TABLE subscriptions ALTER COLUMN platform SET DEFAULT 'system'`,
		`ALTER TABLE subscriptions ALTER COLUMN platform SET NOT NULL`,
		`ALTER TABLE subscriptions ALTER COLUMN environment SET DEFAULT 'prod'`,
		`ALTER TABLE subscriptions ALTER COLUMN environment SET NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_subscriptions_scope ON subscriptions(environment, platform, updated_at DESC)`,
		`CREATE TABLE IF NOT EXISTS subscription_plans (
			id TEXT PRIMARY KEY,
			key TEXT NOT NULL,
			name TEXT NOT NULL,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
			coins_granted INTEGER NOT NULL DEFAULT 0,
			price_usd NUMERIC(12,2) NOT NULL DEFAULT 0,
			period TEXT NOT NULL CHECK (period IN ('week', 'month', 'year')),
			product_id TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT true,
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(environment, platform, key)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_subscription_plans_scope ON subscription_plans(environment, platform, sort_order)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_plans_product ON subscription_plans(environment, platform, product_id) WHERE product_id <> ''`,
		`CREATE TABLE IF NOT EXISTS coin_packs (
			id TEXT PRIMARY KEY,
			key TEXT NOT NULL,
			name TEXT NOT NULL,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
			coins INTEGER NOT NULL,
			price_usd NUMERIC(12,2) NOT NULL DEFAULT 0,
			product_id TEXT NOT NULL DEFAULT '',
			popular BOOLEAN NOT NULL DEFAULT false,
			enabled BOOLEAN NOT NULL DEFAULT true,
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(environment, platform, key)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_coin_packs_scope ON coin_packs(environment, platform, sort_order)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_packs_product ON coin_packs(environment, platform, product_id) WHERE product_id <> ''`,
		`INSERT INTO subscription_plans
			(id,key,name,environment,platform,coins_granted,price_usd,period,product_id,enabled,sort_order)
		 SELECT 'catalog-' || env || '-' || platform || '-' || key,key,name,env,platform,coins,price,period,product_id,true,sort_order
		 FROM (VALUES
			('plus_monthly','Vita Plus Monthly',500,9.99::numeric,'month','vita.plus.monthly',10),
			('plus_yearly','Vita Plus Yearly',500,79.99::numeric,'year','vita.plus.yearly',20),
			('premium_monthly','Vita Premium Monthly',1200,19.99::numeric,'month','vita.premium.monthly',30),
			('premium_yearly','Vita Premium Yearly',1200,159.99::numeric,'year','vita.premium.yearly',40)
		 ) AS products(key,name,coins,price,period,product_id,sort_order)
		 CROSS JOIN (VALUES('dev'),('beta'),('prod')) AS environments(env)
		 CROSS JOIN (VALUES('ios'),('android')) AS platforms(platform)
		 ON CONFLICT(environment,platform,key) DO UPDATE SET
			name=EXCLUDED.name,coins_granted=EXCLUDED.coins_granted,price_usd=EXCLUDED.price_usd,
			period=EXCLUDED.period,product_id=EXCLUDED.product_id,sort_order=EXCLUDED.sort_order`,
		`INSERT INTO coin_packs
			(id,key,name,environment,platform,coins,price_usd,product_id,popular,enabled,sort_order)
		 SELECT 'catalog-' || env || '-' || platform || '-' || key,key,name,env,platform,coins,price,product_id,popular,true,sort_order
		 FROM (VALUES
			('coins_100','100 Coins',100,1.99::numeric,'vita.coins.100',false,10),
			('coins_500','500 Coins',500,7.99::numeric,'vita.coins.500',true,20),
			('coins_1200','1,200 Coins',1200,14.99::numeric,'vita.coins.1200',false,30)
		 ) AS products(key,name,coins,price,product_id,popular,sort_order)
		 CROSS JOIN (VALUES('dev'),('beta'),('prod')) AS environments(env)
		 CROSS JOIN (VALUES('ios'),('android')) AS platforms(platform)
		 ON CONFLICT(environment,platform,key) DO UPDATE SET product_id=EXCLUDED.product_id`,
		`CREATE TABLE IF NOT EXISTS billing_purchases (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			transaction_id TEXT NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('subscription', 'coin_pack')),
			provider TEXT NOT NULL,
			platform TEXT NOT NULL,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			product_id TEXT NOT NULL DEFAULT '',
			amount_minor BIGINT,
			currency TEXT NOT NULL DEFAULT '',
			credits INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'paid',
			purchased_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(provider, transaction_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_billing_purchases_scope ON billing_purchases(environment, platform, purchased_at DESC)`,
		`CREATE TABLE IF NOT EXISTS admin_grant_operations (
			id TEXT PRIMARY KEY,
			operator_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
			operator_email TEXT NOT NULL,
			target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			target_email TEXT NOT NULL,
			operation_type TEXT NOT NULL CHECK (operation_type IN ('coins', 'subscription')),
			coins INTEGER NOT NULL DEFAULT 0,
			plan_id TEXT REFERENCES subscription_plans(id) ON DELETE SET NULL,
			plan_name TEXT NOT NULL DEFAULT '',
			subscription_id TEXT REFERENCES subscriptions(id) ON DELETE SET NULL,
			expires_at TIMESTAMP,
			note TEXT NOT NULL DEFAULT '',
			platform TEXT NOT NULL DEFAULT 'system',
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_admin_grant_operations_target ON admin_grant_operations(target_user_id, created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_admin_grant_operations_operator ON admin_grant_operations(operator_user_id, created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS companions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			name TEXT NOT NULL,
			gender TEXT,
			persona TEXT,
			appearance TEXT,
			city TEXT,
			occupation TEXT,
			interests TEXT,
			relationship_stage TEXT DEFAULT 'stranger',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`DO $$ BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='credit_spends_companion_id_fkey') THEN
				ALTER TABLE credit_spends ADD CONSTRAINT credit_spends_companion_id_fkey FOREIGN KEY(companion_id) REFERENCES companions(id) ON DELETE SET NULL;
			END IF;
		END $$`,
		`CREATE TABLE IF NOT EXISTS conversations (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			companion_id TEXT NOT NULL REFERENCES companions(id),
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE conversations ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMP`,
		`CREATE TABLE IF NOT EXISTS messages (
			id TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL REFERENCES conversations(id),
			sender_type TEXT NOT NULL,
			message_type TEXT DEFAULT 'text',
			content TEXT,
			media_url TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_conversations_user_companion ON conversations(user_id,companion_id)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id,created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS memories (
			id TEXT PRIMARY KEY,
			companion_id TEXT NOT NULL REFERENCES companions(id),
			type TEXT,
			content TEXT,
			importance INTEGER DEFAULT 0,
			event_time TIMESTAMP,
			embedding TEXT,
			metadata TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE memories ADD COLUMN IF NOT EXISTS follow_up_at TIMESTAMP`,
		`ALTER TABLE memories ADD COLUMN IF NOT EXISTS follow_up_claimed_at TIMESTAMP`,
		`ALTER TABLE memories ADD COLUMN IF NOT EXISTS followed_up_at TIMESTAMP`,
		`CREATE INDEX IF NOT EXISTS idx_memories_follow_up ON memories(follow_up_at) WHERE followed_up_at IS NULL`,
		`CREATE TABLE IF NOT EXISTS life_events (
			id TEXT PRIMARY KEY,
			companion_id TEXT NOT NULL REFERENCES companions(id),
			event_type TEXT,
			title TEXT,
			description TEXT,
			location TEXT,
			start_time TIMESTAMP,
			end_time TIMESTAMP,
			emotion TEXT,
			importance INTEGER DEFAULT 0,
			user_relevance INTEGER DEFAULT 0,
			shareability BOOLEAN DEFAULT false,
			status TEXT DEFAULT 'active'
		)`,
		`CREATE TABLE IF NOT EXISTS relationship_states (
			companion_id TEXT PRIMARY KEY REFERENCES companions(id),
			intimacy INTEGER DEFAULT 0,
			trust INTEGER DEFAULT 0,
			familiarity INTEGER DEFAULT 0,
			enthusiasm INTEGER NOT NULL DEFAULT 0,
			shared_history TEXT,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE relationship_states ADD COLUMN IF NOT EXISTS enthusiasm INTEGER NOT NULL DEFAULT 0`,
		`CREATE TABLE IF NOT EXISTS companion_states (
			companion_id TEXT PRIMARY KEY REFERENCES companions(id),
			mood INTEGER DEFAULT 50,
			energy INTEGER DEFAULT 50,
			stress INTEGER DEFAULT 50,
			social_energy INTEGER DEFAULT 50,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS ai_providers (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('openai', 'anthropic')),
			base_url TEXT NOT NULL,
			api_key_ciphertext TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS ai_models (
			id TEXT PRIMARY KEY,
			provider_id TEXT NOT NULL REFERENCES ai_providers(id) ON DELETE CASCADE,
			model_name TEXT NOT NULL,
			display_name TEXT NOT NULL,
			capabilities JSONB NOT NULL DEFAULT '["text"]'::jsonb,
			enabled BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(provider_id, model_name)
		)`,
		`ALTER TABLE ai_models ADD COLUMN IF NOT EXISTS configured_scenarios JSONB NOT NULL DEFAULT '[]'::jsonb`,
		`CREATE TABLE IF NOT EXISTS ai_model_subscription_plans (
			model_id TEXT NOT NULL REFERENCES ai_models(id) ON DELETE CASCADE,
			subscription_plan_id TEXT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY(model_id, subscription_plan_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_ai_model_subscription_plans_plan ON ai_model_subscription_plans(subscription_plan_id, model_id)`,
		`UPDATE ai_models SET configured_scenarios =
			(CASE WHEN capabilities ? 'text' THEN '["text_chat","text_life_plan","text_proactive","text_character_profile"]'::jsonb ELSE '[]'::jsonb END) ||
			(CASE WHEN capabilities ? 'image' THEN '["image_life_photo","image_requested_photo"]'::jsonb ELSE '[]'::jsonb END) ||
			(CASE WHEN capabilities ? 'audio' THEN '["audio_transcription","audio_speech"]'::jsonb ELSE '[]'::jsonb END) ||
			(CASE WHEN capabilities ? 'video' THEN '["video_life_clip","video_realtime_avatar"]'::jsonb ELSE '[]'::jsonb END)
		 WHERE configured_scenarios = '[]'::jsonb`,
		`CREATE TABLE IF NOT EXISTS agent_settings (
			id TEXT PRIMARY KEY DEFAULT 'default',
			chat_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			life_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			proactive_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			daily_event_min INTEGER NOT NULL DEFAULT 8,
			daily_event_max INTEGER NOT NULL DEFAULT 15,
			daily_proactive_limit INTEGER NOT NULL DEFAULT 4,
			quiet_hours_start INTEGER NOT NULL DEFAULT 23,
			quiet_hours_end INTEGER NOT NULL DEFAULT 8,
			free_default_chat_hours INTEGER NOT NULL DEFAULT 24,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE agent_settings ADD COLUMN IF NOT EXISTS free_default_chat_hours INTEGER NOT NULL DEFAULT 24`,
		`ALTER TABLE agent_settings ADD COLUMN IF NOT EXISTS image_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL`,
		`ALTER TABLE agent_settings ADD COLUMN IF NOT EXISTS daily_life_photo_limit INTEGER NOT NULL DEFAULT 2`,
		`ALTER TABLE agent_settings ADD COLUMN IF NOT EXISTS transcription_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL`,
		`ALTER TABLE agent_settings ADD COLUMN IF NOT EXISTS speech_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL`,
		`INSERT INTO agent_settings (id) VALUES ('default') ON CONFLICT (id) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS agent_media_routes (
			route_key TEXT PRIMARY KEY,
			media_type TEXT NOT NULL CHECK (media_type IN ('text','image','audio','video')),
			enabled BOOLEAN NOT NULL DEFAULT false,
			primary_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			fallback_model_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`DO $$ BEGIN
			IF EXISTS (
				SELECT 1 FROM pg_constraint
				WHERE conname='agent_media_routes_media_type_check'
				AND pg_get_constraintdef(oid) NOT LIKE '%''text''%'
			) THEN
				ALTER TABLE agent_media_routes DROP CONSTRAINT agent_media_routes_media_type_check;
				ALTER TABLE agent_media_routes ADD CONSTRAINT agent_media_routes_media_type_check CHECK (media_type IN ('text','image','audio','video'));
			END IF;
		END $$`,
		`INSERT INTO agent_media_routes(route_key,media_type) VALUES
			('text_chat','text'),('text_life_plan','text'),('text_proactive','text'),('text_character_profile','text'),
			('image_life_photo','image'),('image_requested_photo','image'),
			('audio_transcription','audio'),('audio_speech','audio'),
			('video_life_clip','video'),('video_realtime_avatar','video')
		ON CONFLICT(route_key) DO NOTHING`,
		`UPDATE ai_models SET configured_scenarios=configured_scenarios || '["text_character_profile"]'::jsonb
		WHERE capabilities ? 'text' AND NOT configured_scenarios ? 'text_character_profile'`,
		`UPDATE agent_media_routes r SET primary_model_id=s.chat_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.chat_model_id IS NOT NULL
		AND r.route_key='text_chat' AND r.primary_model_id IS NULL`,
		`UPDATE agent_media_routes r SET primary_model_id=s.life_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.life_model_id IS NOT NULL
		AND r.route_key='text_life_plan' AND r.primary_model_id IS NULL`,
		`UPDATE agent_media_routes r SET primary_model_id=s.proactive_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.proactive_model_id IS NOT NULL
		AND r.route_key='text_proactive' AND r.primary_model_id IS NULL`,
		`UPDATE agent_media_routes r SET primary_model_id=s.image_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.image_model_id IS NOT NULL
		AND r.route_key IN ('image_life_photo','image_requested_photo') AND r.primary_model_id IS NULL`,
		`UPDATE agent_media_routes r SET primary_model_id=s.transcription_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.transcription_model_id IS NOT NULL
		AND r.route_key='audio_transcription' AND r.primary_model_id IS NULL`,
		`UPDATE agent_media_routes r SET primary_model_id=s.speech_model_id,enabled=true
		FROM agent_settings s WHERE s.id='default' AND s.speech_model_id IS NOT NULL
		AND r.route_key='audio_speech' AND r.primary_model_id IS NULL`,
		`CREATE TABLE IF NOT EXISTS companion_portraits (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			image_url TEXT NOT NULL,
			gender TEXT NOT NULL DEFAULT 'custom',
			personality_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
			is_default BOOLEAN NOT NULL DEFAULT false,
			enabled BOOLEAN NOT NULL DEFAULT true,
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE companion_portraits ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT false`,
		`INSERT INTO companion_portraits (id,name,image_url,gender,personality_tags,enabled,sort_order) VALUES
			('system-mia','Mia','asset://assets/companions/mia.png','girlfriend','["warm","independent","thoughtful"]'::jsonb,true,10),
			('system-nora','Nora','asset://assets/companions/nora.png','girlfriend','["witty","curious","outgoing"]'::jsonb,true,20),
			('system-leo','Leo','asset://assets/companions/leo.png','boyfriend','["calm","creative","independent"]'::jsonb,true,30),
			('system-kai','Kai','asset://assets/companions/kai.png','boyfriend','["thoughtful","playful","ambitious"]'::jsonb,true,40)
		ON CONFLICT (id) DO UPDATE SET image_url=EXCLUDED.image_url, personality_tags=EXCLUDED.personality_tags`,
		`UPDATE companion_portraits SET is_default=true WHERE id='system-mia' AND NOT EXISTS (SELECT 1 FROM companion_portraits WHERE is_default=true)`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS personality_tags JSONB NOT NULL DEFAULT '[]'::jsonb`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS speaking_style TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS likes TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS dislikes TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS life_habits TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS life_goal TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS backstory TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS portrait_id TEXT REFERENCES companion_portraits(id) ON DELETE SET NULL`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS creation_source TEXT NOT NULL DEFAULT 'tags_portrait'`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS proactive_enabled BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT false`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS life_enabled BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS friendship_active BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS subscription_paused_at TIMESTAMP`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS purge_after TIMESTAMP`,
		`CREATE INDEX IF NOT EXISTS idx_companions_purge_after ON companions(purge_after) WHERE deleted_at IS NOT NULL`,
		// Reserved for the upcoming voice-message capability. Keeping the
		// provider-specific settings in JSON avoids another migration when the
		// first TTS provider is selected; voice stays off for the text-only app.
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS voice_enabled BOOLEAN NOT NULL DEFAULT false`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS voice_config JSONB NOT NULL DEFAULT '{}'::jsonb`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_companions_default_portrait_user ON companions(user_id, portrait_id) WHERE is_default=true AND portrait_id IS NOT NULL`,
		`CREATE TABLE IF NOT EXISTS default_companion_trials (
			user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			expires_at TIMESTAMP NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS companion_gifts (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			coins INTEGER NOT NULL CHECK (coins > 0),
			intimacy_delta INTEGER NOT NULL DEFAULT 0,
			enthusiasm_delta INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_companion_gifts_companion ON companion_gifts(companion_id, created_at DESC)`,
		`ALTER TABLE companion_gifts ADD COLUMN IF NOT EXISTS product_key TEXT NOT NULL DEFAULT 'gift_coins'`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS equipped_outfit_key TEXT NOT NULL DEFAULT ''`,
		`CREATE TABLE IF NOT EXISTS ai_pet_breeds (
			id TEXT PRIMARY KEY,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			name TEXT NOT NULL,
			species TEXT NOT NULL,
			personality TEXT NOT NULL DEFAULT '',
			description TEXT NOT NULL DEFAULT '',
			avatar_url TEXT NOT NULL DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			enabled BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_ai_pet_breeds_scope ON ai_pet_breeds(environment,enabled,sort_order,name)`,
		`INSERT INTO ai_pet_breeds(id,environment,name,species,personality,description,avatar_url,sort_order,enabled)
		 SELECT 'system-ai-pet-' || env || '-' || slug,env,name,species,personality,description,avatar_url,sort_order,true
		 FROM (VALUES('dev'),('beta'),('prod')) AS environments(env)
		 CROSS JOIN (VALUES
			('orange-tabby','Mochi','Cat','Playful and curious','A sunny orange tabby who loves snacks, warm naps, and following you everywhere.','asset://assets/ai_pets/cat_orange.png',10),
			('tuxedo-cat','Oreo','Cat','Clever and affectionate','A smart tuxedo cat with a gentle heart and a talent for cheering you up.','asset://assets/ai_pets/cat_tuxedo.png',20),
			('ragdoll-cat','Luna','Cat','Calm and sweet','A soft ragdoll cat who enjoys quiet company, cozy evenings, and kind conversations.','asset://assets/ai_pets/cat_ragdoll.png',30),
			('corgi','Biscuit','Dog','Cheerful and energetic','A happy corgi who turns every day into a tiny adventure.','asset://assets/ai_pets/dog_corgi.png',40),
			('shiba','Momo','Dog','Loyal and independent','A confident Shiba Inu who may act cool but always stays close when you need a friend.','asset://assets/ai_pets/dog_shiba.png',50),
			('golden-retriever','Sunny','Dog','Friendly and caring','A warm golden retriever who loves playtime, encouragement, and making new memories.','asset://assets/ai_pets/dog_retriever.png',60)
		 ) AS defaults(slug,name,species,personality,description,avatar_url,sort_order)
		 ON CONFLICT(id) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS ai_pet_breed_subscription_plans (
			breed_id TEXT NOT NULL REFERENCES ai_pet_breeds(id) ON DELETE CASCADE,
			subscription_plan_id TEXT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY(breed_id,subscription_plan_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_ai_pet_breed_plans_plan ON ai_pet_breed_subscription_plans(subscription_plan_id,breed_id)`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS pet_breed_id TEXT REFERENCES ai_pet_breeds(id) ON DELETE SET NULL`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS avatar_url TEXT NOT NULL DEFAULT ''`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_companions_user_pet_breed ON companions(user_id,pet_breed_id) WHERE pet_breed_id IS NOT NULL AND deleted_at IS NULL`,
		`CREATE TABLE IF NOT EXISTS ai_pet_states (
			companion_id TEXT PRIMARY KEY REFERENCES companions(id) ON DELETE CASCADE,
			hunger INTEGER NOT NULL DEFAULT 80 CHECK (hunger BETWEEN 0 AND 100),
			happiness INTEGER NOT NULL DEFAULT 70 CHECK (happiness BETWEEN 0 AND 100),
			energy INTEGER NOT NULL DEFAULT 80 CHECK (energy BETWEEN 0 AND 100),
			health INTEGER NOT NULL DEFAULT 100 CHECK (health BETWEEN 0 AND 100),
			experience INTEGER NOT NULL DEFAULT 0 CHECK (experience >= 0),
			level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
			last_fed_at TIMESTAMP,
			last_decay_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`ALTER TABLE credit_products DROP CONSTRAINT IF EXISTS credit_products_category_check`,
		`ALTER TABLE credit_products ADD CONSTRAINT credit_products_category_check CHECK (category IN ('gift','photo','voice','date','keepsake','outfit','call','pet'))`,
		`INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
		 SELECT env,'ai_pet_feed','pet','credits.product.petFeed.name','credits.product.petFeed.description','🥣',5,true,5,'{"hidden_from_catalog":true}'::jsonb
		 FROM (VALUES('dev'),('beta'),('prod')) AS environments(env)
		 ON CONFLICT(environment,product_key) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS companion_outfits (
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			product_key TEXT NOT NULL,
			acquired_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY(user_id,companion_id,product_key)
		)`,
		`CREATE TABLE IF NOT EXISTS companion_keepsakes (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			title TEXT NOT NULL,
			content TEXT NOT NULL,
			payload JSONB NOT NULL DEFAULT '{}'::jsonb,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_companion_keepsakes_companion ON companion_keepsakes(companion_id,created_at DESC)`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'user'`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS life_event_id TEXT`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS delivery_status TEXT NOT NULL DEFAULT 'delivered'`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS local_date DATE`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS sequence INTEGER NOT NULL DEFAULT 0`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS generation_source TEXT NOT NULL DEFAULT 'agent'`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS shared_at TIMESTAMP`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_life_events_day_sequence ON life_events(companion_id, local_date, sequence) WHERE local_date IS NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_life_events_due ON life_events(start_time, shareability, shared_at)`,
		`CREATE TABLE IF NOT EXISTS companion_relationships (
			id TEXT PRIMARY KEY,
			companion_a_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			companion_b_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			relationship_type TEXT NOT NULL DEFAULT 'acquaintance',
			status TEXT NOT NULL DEFAULT 'active',
			familiarity INTEGER NOT NULL DEFAULT 0,
			affinity INTEGER NOT NULL DEFAULT 0,
			shared_context JSONB NOT NULL DEFAULT '{}'::jsonb,
			met_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			last_interaction_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			CHECK (companion_a_id < companion_b_id),
			UNIQUE(companion_a_id, companion_b_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_companion_relationships_a ON companion_relationships(companion_a_id,status)`,
		`CREATE INDEX IF NOT EXISTS idx_companion_relationships_b ON companion_relationships(companion_b_id,status)`,
		`CREATE TABLE IF NOT EXISTS companion_connection_days (
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			local_date DATE NOT NULL DEFAULT CURRENT_DATE,
			relationship_id TEXT NOT NULL REFERENCES companion_relationships(id) ON DELETE CASCADE,
			PRIMARY KEY(companion_id,local_date)
		)`,
		`CREATE TABLE IF NOT EXISTS companion_social_events (
			id TEXT PRIMARY KEY,
			relationship_id TEXT NOT NULL REFERENCES companion_relationships(id) ON DELETE CASCADE,
			actor_companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			related_companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			event_type TEXT NOT NULL DEFAULT 'shared_activity',
			title TEXT NOT NULL DEFAULT '',
			description TEXT NOT NULL DEFAULT '',
			location TEXT NOT NULL DEFAULT '',
			start_time TIMESTAMP NOT NULL,
			end_time TIMESTAMP NOT NULL,
			emotion TEXT NOT NULL DEFAULT '',
			importance INTEGER NOT NULL DEFAULT 0,
			shareability BOOLEAN NOT NULL DEFAULT false,
			local_date DATE NOT NULL,
			payload JSONB NOT NULL DEFAULT '{}'::jsonb,
			generation_source TEXT NOT NULL DEFAULT 'agent',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(relationship_id, local_date)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_companion_social_events_due ON companion_social_events(start_time,shareability)`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS related_companion_id TEXT REFERENCES companions(id) ON DELETE SET NULL`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS social_event_id TEXT REFERENCES companion_social_events(id) ON DELETE SET NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_life_events_social_companion ON life_events(social_event_id,companion_id) WHERE social_event_id IS NOT NULL`,
		`CREATE TABLE IF NOT EXISTS moment_posts (
			id TEXT PRIMARY KEY,
			author_companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			life_event_id TEXT REFERENCES life_events(id) ON DELETE SET NULL,
			social_event_id TEXT REFERENCES companion_social_events(id) ON DELETE SET NULL,
			post_type TEXT NOT NULL DEFAULT 'text' CHECK (post_type IN ('text','image','image_text')),
			content TEXT NOT NULL DEFAULT '',
			media_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
			payload JSONB NOT NULL DEFAULT '{}'::jsonb,
			visibility TEXT NOT NULL DEFAULT 'connections',
			published_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			CHECK (content <> '' OR jsonb_array_length(media_urls) > 0)
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_moment_posts_life_event ON moment_posts(life_event_id) WHERE life_event_id IS NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_moment_posts_published ON moment_posts(published_at DESC)`,
		`CREATE TABLE IF NOT EXISTS companion_days (
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			local_date DATE NOT NULL,
			timezone TEXT NOT NULL DEFAULT 'UTC',
			status TEXT NOT NULL DEFAULT 'pending',
			event_count INTEGER NOT NULL DEFAULT 0,
			generated_at TIMESTAMP,
			last_error TEXT NOT NULL DEFAULT '',
			PRIMARY KEY(companion_id, local_date)
		)`,
		`CREATE TABLE IF NOT EXISTS notification_outbox (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
			channel TEXT NOT NULL DEFAULT 'push',
			payload JSONB NOT NULL DEFAULT '{}'::jsonb,
			status TEXT NOT NULL DEFAULT 'pending',
			attempts INTEGER NOT NULL DEFAULT 0,
			available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			sent_at TIMESTAMP,
			last_error TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_message_channel ON notification_outbox(message_id, channel)`,
		`CREATE TABLE IF NOT EXISTS pending_agent_replies (
			conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			trigger_message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
			scheduled_at TIMESTAMP NOT NULL,
			status TEXT NOT NULL DEFAULT 'pending',
			attempts INTEGER NOT NULL DEFAULT 0,
			last_error TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_pending_agent_replies_due ON pending_agent_replies(status,scheduled_at)`,
		`CREATE TABLE IF NOT EXISTS media_assets (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			kind TEXT NOT NULL CHECK(kind IN ('image','audio')),
			mime_type TEXT NOT NULL,
			data BYTEA NOT NULL,
			size_bytes INTEGER NOT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_media_assets_user ON media_assets(user_id,created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS onboarding_configs (
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
			enabled BOOLEAN NOT NULL DEFAULT true,
			revision INTEGER NOT NULL DEFAULT 1,
			pages JSONB NOT NULL DEFAULT '[]'::jsonb,
			updated_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY(environment, platform)
		)`,
		`INSERT INTO onboarding_configs(environment,platform) VALUES
			('dev','ios'),('dev','android'),('beta','ios'),('beta','android'),('prod','ios'),('prod','android')
		ON CONFLICT(environment,platform) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS whats_new_campaigns (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
			min_app_version TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT false,
			starts_at TIMESTAMP,
			ends_at TIMESTAMP,
			pages JSONB NOT NULL DEFAULT '[]'::jsonb,
			updated_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_whats_new_scope ON whats_new_campaigns(environment,platform,enabled,starts_at,ends_at)`,
		`CREATE TABLE IF NOT EXISTS social_media_links (
			environment TEXT PRIMARY KEY CHECK (environment IN ('dev', 'beta', 'prod')),
			instagram_url TEXT NOT NULL DEFAULT '',
			tiktok_url TEXT NOT NULL DEFAULT '',
			x_url TEXT NOT NULL DEFAULT '',
			discord_url TEXT NOT NULL DEFAULT '',
			updated_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`INSERT INTO social_media_links(environment) VALUES('dev'),('beta'),('prod')
		ON CONFLICT(environment) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS analytics_events (
			id TEXT PRIMARY KEY,
			user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
			anonymous_id TEXT NOT NULL DEFAULT '',
			session_id TEXT NOT NULL DEFAULT '',
			event_name TEXT NOT NULL,
			category TEXT NOT NULL DEFAULT 'general',
			properties JSONB NOT NULL DEFAULT '{}'::jsonb,
			platform TEXT NOT NULL DEFAULT 'unknown',
			environment TEXT NOT NULL DEFAULT 'dev',
			app_version TEXT NOT NULL DEFAULT '',
			locale TEXT NOT NULL DEFAULT '',
			client_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_analytics_events_user_time ON analytics_events(user_id,created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_analytics_events_install ON analytics_events(anonymous_id,created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_analytics_events_scope ON analytics_events(environment,platform,event_name,created_at DESC)`,
		`ALTER TABLE notification_outbox ALTER COLUMN channel SET DEFAULT 'push'`,
		`CREATE TABLE IF NOT EXISTS device_push_tokens (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			token TEXT NOT NULL UNIQUE,
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
			device_id TEXT NOT NULL DEFAULT '',
			locale TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT true,
			last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user ON device_push_tokens(user_id, enabled)`,
		`CREATE TABLE IF NOT EXISTS agent_runs (
			id TEXT PRIMARY KEY,
			companion_id TEXT REFERENCES companions(id) ON DELETE SET NULL,
			kind TEXT NOT NULL,
			model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			status TEXT NOT NULL,
			input_summary TEXT NOT NULL DEFAULT '',
			error TEXT NOT NULL DEFAULT '',
			started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			finished_at TIMESTAMP
		)`,
		`INSERT INTO roles (id, name, description) VALUES ('user', 'user', 'Regular user') ON CONFLICT (id) DO NOTHING`,
		`INSERT INTO roles (id, name, description) VALUES ('admin', 'admin', 'Administrator') ON CONFLICT (id) DO NOTHING`,
	}

	for _, q := range queries {
		preview := q
		if len(preview) > 60 {
			preview = preview[:60]
		}
		fmt.Printf("Executing migration: %s...\n", preview)
		if _, err := db.Exec(q); err != nil {
			return fmt.Errorf("failed to execute: %w", err)
		}
	}
	return nil
}
