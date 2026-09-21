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

INSERT INTO ai_pet_breeds(
    id, environment, name, species, personality, description,
    avatar_url, sort_order, enabled
)
SELECT
    'system-ai-pet-' || env || '-' || slug,
    env, name, species, personality, description, avatar_url, sort_order, true
FROM (VALUES ('dev'), ('beta'), ('prod')) AS environments(env)
CROSS JOIN (VALUES
    ('orange-tabby', 'Mochi', 'Cat', 'Playful and curious', 'A sunny orange tabby who loves snacks, warm naps, and following you everywhere.', 'asset://assets/ai_pets/cat_orange.png', 10),
    ('tuxedo-cat', 'Oreo', 'Cat', 'Clever and affectionate', 'A smart tuxedo cat with a gentle heart and a talent for cheering you up.', 'asset://assets/ai_pets/cat_tuxedo.png', 20),
    ('ragdoll-cat', 'Luna', 'Cat', 'Calm and sweet', 'A soft ragdoll cat who enjoys quiet company, cozy evenings, and kind conversations.', 'asset://assets/ai_pets/cat_ragdoll.png', 30),
    ('corgi', 'Biscuit', 'Dog', 'Cheerful and energetic', 'A happy corgi who turns every day into a tiny adventure.', 'asset://assets/ai_pets/dog_corgi.png', 40),
    ('shiba', 'Momo', 'Dog', 'Loyal and independent', 'A confident Shiba Inu who may act cool but always stays close when you need a friend.', 'asset://assets/ai_pets/dog_shiba.png', 50),
    ('golden-retriever', 'Sunny', 'Dog', 'Friendly and caring', 'A warm golden retriever who loves playtime, encouragement, and making new memories.', 'asset://assets/ai_pets/dog_retriever.png', 60)
) AS defaults(slug, name, species, personality, description, avatar_url, sort_order)
ON CONFLICT(id) DO NOTHING;

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
