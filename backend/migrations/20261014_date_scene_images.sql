CREATE TABLE IF NOT EXISTS date_scene_image_jobs (
    event_id TEXT NOT NULL REFERENCES life_events(id) ON DELETE CASCADE,
    phase TEXT NOT NULL CHECK (phase IN ('arrival','together','farewell')),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    retry_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at TIMESTAMPTZ,
    PRIMARY KEY (event_id,phase)
);
CREATE INDEX IF NOT EXISTS date_scene_image_jobs_pending
ON date_scene_image_jobs(retry_at) WHERE status <> 'completed' AND attempts < 3;
