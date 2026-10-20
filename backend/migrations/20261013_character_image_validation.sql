ALTER TABLE media_assets ADD COLUMN IF NOT EXISTS character_image_validated BOOLEAN NOT NULL DEFAULT false;
INSERT INTO agent_media_routes(route_key,media_type,enabled,fallback_model_ids)
VALUES ('text_character_image_validation','text',false,'[]'::jsonb)
ON CONFLICT(route_key) DO NOTHING;
