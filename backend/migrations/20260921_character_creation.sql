UPDATE ai_models
SET configured_scenarios = configured_scenarios || '["text_character_profile"]'::jsonb
WHERE capabilities ? 'text' AND NOT configured_scenarios ? 'text_character_profile';

INSERT INTO agent_media_routes(route_key,media_type,enabled)
VALUES ('text_character_profile','text',false)
ON CONFLICT(route_key) DO NOTHING;
