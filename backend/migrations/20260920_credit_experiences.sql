CREATE TABLE IF NOT EXISTS credit_products (
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
);

INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
SELECT env,key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::jsonb FROM (VALUES
    ('gift_coffee','gift','experience.gift.coffee','experience.gift.coffee.desc','☕',10,true,10,'{"intimacy":1,"enthusiasm":2}'),
    ('gift_flowers','gift','experience.gift.flowers','experience.gift.flowers.desc','💐',30,true,20,'{"intimacy":2,"enthusiasm":4}'),
    ('gift_cake','gift','experience.gift.cake','experience.gift.cake.desc','🎂',50,true,30,'{"intimacy":3,"enthusiasm":6}'),
    ('gift_keepsake','gift','experience.gift.keepsake','experience.gift.keepsake.desc','🎁',100,true,40,'{"intimacy":5,"enthusiasm":8}'),
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
ON CONFLICT(environment,product_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS credit_spends (
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
);

CREATE INDEX IF NOT EXISTS idx_credit_spends_user ON credit_spends(user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_credit_spends_status ON credit_spends(status,created_at);
ALTER TABLE credit_transactions ADD COLUMN IF NOT EXISTS spend_id TEXT REFERENCES credit_spends(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_credit_transactions_spend ON credit_transactions(spend_id);

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='credit_spends_companion_id_fkey') THEN
        ALTER TABLE credit_spends ADD CONSTRAINT credit_spends_companion_id_fkey
            FOREIGN KEY(companion_id) REFERENCES companions(id) ON DELETE SET NULL;
    END IF;
END $$;

ALTER TABLE companion_gifts ADD COLUMN IF NOT EXISTS product_key TEXT NOT NULL DEFAULT 'gift_coins';
ALTER TABLE companions ADD COLUMN IF NOT EXISTS equipped_outfit_key TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS companion_outfits (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    product_key TEXT NOT NULL,
    acquired_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(user_id,companion_id,product_key)
);

CREATE TABLE IF NOT EXISTS companion_keepsakes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_companion_keepsakes_companion ON companion_keepsakes(companion_id,created_at DESC);
