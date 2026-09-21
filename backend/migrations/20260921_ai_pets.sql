CREATE TABLE IF NOT EXISTS ai_pet_breeds (
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
);

CREATE INDEX IF NOT EXISTS idx_ai_pet_breeds_scope
    ON ai_pet_breeds(environment, enabled, sort_order, name);

CREATE TABLE IF NOT EXISTS ai_pet_breed_subscription_plans (
    breed_id TEXT NOT NULL REFERENCES ai_pet_breeds(id) ON DELETE CASCADE,
    subscription_plan_id TEXT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (breed_id, subscription_plan_id)
);

CREATE INDEX IF NOT EXISTS idx_ai_pet_breed_plans_plan
    ON ai_pet_breed_subscription_plans(subscription_plan_id, breed_id);

ALTER TABLE companions ADD COLUMN IF NOT EXISTS pet_breed_id TEXT REFERENCES ai_pet_breeds(id) ON DELETE SET NULL;
ALTER TABLE companions ADD COLUMN IF NOT EXISTS avatar_url TEXT NOT NULL DEFAULT '';
ALTER TABLE companions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;
CREATE UNIQUE INDEX IF NOT EXISTS idx_companions_user_pet_breed
    ON companions(user_id, pet_breed_id) WHERE pet_breed_id IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS ai_pet_states (
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
);

ALTER TABLE credit_products DROP CONSTRAINT IF EXISTS credit_products_category_check;
ALTER TABLE credit_products ADD CONSTRAINT credit_products_category_check
    CHECK (category IN ('gift','photo','voice','date','keepsake','outfit','call','pet'));

INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
SELECT env,'ai_pet_feed','pet','credits.product.petFeed.name','credits.product.petFeed.description','🥣',5,true,5,
       '{"hidden_from_catalog":true}'::jsonb
FROM (VALUES ('dev'),('beta'),('prod')) AS environments(env)
ON CONFLICT(environment,product_key) DO NOTHING;
