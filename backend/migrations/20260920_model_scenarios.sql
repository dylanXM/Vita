ALTER TABLE ai_models
    ADD COLUMN IF NOT EXISTS configured_scenarios JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE ai_models SET configured_scenarios =
    (CASE WHEN capabilities ? 'text' THEN '["text_chat","text_life_plan","text_proactive","text_character_profile"]'::jsonb ELSE '[]'::jsonb END) ||
    (CASE WHEN capabilities ? 'image' THEN '["image_life_photo","image_requested_photo"]'::jsonb ELSE '[]'::jsonb END) ||
    (CASE WHEN capabilities ? 'audio' THEN '["audio_transcription","audio_speech"]'::jsonb ELSE '[]'::jsonb END) ||
    (CASE WHEN capabilities ? 'video' THEN '["video_life_clip","video_realtime_avatar"]'::jsonb ELSE '[]'::jsonb END)
WHERE configured_scenarios = '[]'::jsonb;
