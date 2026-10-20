BEGIN;

CREATE TABLE IF NOT EXISTS media_storage_settings (
    environment TEXT PRIMARY KEY CHECK (environment IN ('dev', 'beta', 'prod')),
    active_provider TEXT NOT NULL DEFAULT 'postgres'
        CHECK (active_provider IN ('postgres', 'r2', 'cos')),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO media_storage_settings(environment)
VALUES ('dev'), ('beta'), ('prod')
ON CONFLICT(environment) DO NOTHING;

CREATE TABLE IF NOT EXISTS media_storage_configs (
    environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
    provider TEXT NOT NULL CHECK (provider IN ('r2', 'cos')),
    enabled BOOLEAN NOT NULL DEFAULT false,
    endpoint TEXT NOT NULL DEFAULT '',
    bucket TEXT NOT NULL DEFAULT '',
    region TEXT NOT NULL DEFAULT '',
    access_key_ciphertext TEXT NOT NULL DEFAULT '',
    secret_key_ciphertext TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (environment, provider)
);

ALTER TABLE media_assets
    ADD COLUMN IF NOT EXISTS storage_provider TEXT NOT NULL DEFAULT 'postgres';
ALTER TABLE media_assets
    ADD COLUMN IF NOT EXISTS object_key TEXT NOT NULL DEFAULT '';
ALTER TABLE media_assets
    ADD COLUMN IF NOT EXISTS storage_environment TEXT NOT NULL DEFAULT 'prod';

CREATE INDEX IF NOT EXISTS idx_media_assets_storage_object
    ON media_assets(storage_provider, object_key)
    WHERE object_key <> '';

CREATE TABLE IF NOT EXISTS media_object_deletions (
    id BIGSERIAL PRIMARY KEY,
    environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
    storage_provider TEXT NOT NULL CHECK (storage_provider IN ('r2', 'cos')),
    object_key TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(environment, storage_provider, object_key)
);

CREATE OR REPLACE FUNCTION queue_media_object_deletion()
RETURNS trigger AS $$
BEGIN
    IF OLD.storage_provider IN ('r2', 'cos') AND OLD.object_key <> '' THEN
        INSERT INTO media_object_deletions(environment, storage_provider, object_key)
        VALUES (OLD.storage_environment, OLD.storage_provider, OLD.object_key)
        ON CONFLICT(environment, storage_provider, object_key) DO NOTHING;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_queue_media_object_deletion ON media_assets;
CREATE TRIGGER trg_queue_media_object_deletion
AFTER DELETE ON media_assets
FOR EACH ROW EXECUTE FUNCTION queue_media_object_deletion();

COMMIT;
