-- Apply before deploying Backend + Admin with Kie provider support.
ALTER TABLE ai_providers DROP CONSTRAINT IF EXISTS ai_providers_kind_check;
ALTER TABLE ai_providers ADD CONSTRAINT ai_providers_kind_check
    CHECK (kind IN ('openai', 'anthropic', 'kie'));
