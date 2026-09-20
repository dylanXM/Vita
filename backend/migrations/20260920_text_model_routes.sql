ALTER TABLE agent_media_routes DROP CONSTRAINT IF EXISTS agent_media_routes_media_type_check;
ALTER TABLE agent_media_routes ADD CONSTRAINT agent_media_routes_media_type_check
    CHECK (media_type IN ('text','image','audio','video'));

INSERT INTO agent_media_routes(route_key,media_type) VALUES
    ('text_chat','text'),
    ('text_life_plan','text'),
    ('text_proactive','text')
ON CONFLICT(route_key) DO NOTHING;

UPDATE agent_media_routes r SET primary_model_id=s.chat_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.chat_model_id IS NOT NULL
AND r.route_key='text_chat' AND r.primary_model_id IS NULL;

UPDATE agent_media_routes r SET primary_model_id=s.life_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.life_model_id IS NOT NULL
AND r.route_key='text_life_plan' AND r.primary_model_id IS NULL;

UPDATE agent_media_routes r SET primary_model_id=s.proactive_model_id,enabled=true
FROM agent_settings s WHERE s.id='default' AND s.proactive_model_id IS NOT NULL
AND r.route_key='text_proactive' AND r.primary_model_id IS NULL;
