CREATE TABLE IF NOT EXISTS agent_media_routes (
    route_key TEXT PRIMARY KEY,
    media_type TEXT NOT NULL CHECK (media_type IN ('image','audio','video')),
    enabled BOOLEAN NOT NULL DEFAULT false,
    primary_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
    fallback_model_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO agent_media_routes(route_key,media_type) VALUES
    ('image_life_photo','image'),
    ('image_requested_photo','image'),
    ('audio_transcription','audio'),
    ('audio_speech','audio'),
    ('video_life_clip','video'),
    ('video_realtime_avatar','video')
ON CONFLICT(route_key) DO NOTHING;

UPDATE agent_media_routes r SET primary_model_id=s.image_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.image_model_id IS NOT NULL
AND r.route_key IN ('image_life_photo','image_requested_photo') AND r.primary_model_id IS NULL;

UPDATE agent_media_routes r SET primary_model_id=s.transcription_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.transcription_model_id IS NOT NULL
AND r.route_key='audio_transcription' AND r.primary_model_id IS NULL;

UPDATE agent_media_routes r SET primary_model_id=s.speech_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.speech_model_id IS NOT NULL
AND r.route_key='audio_speech' AND r.primary_model_id IS NULL;
