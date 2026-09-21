ALTER TABLE companions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;
ALTER TABLE companions ADD COLUMN IF NOT EXISTS purge_after TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_companions_purge_after
    ON companions(purge_after)
    WHERE deleted_at IS NOT NULL;
