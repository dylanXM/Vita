-- Config edits are rare; a statement-level trigger advances one small row.
CREATE TABLE IF NOT EXISTS app_config_versions (
    resource TEXT PRIMARY KEY,
    revision BIGINT NOT NULL DEFAULT 1
);
INSERT INTO app_config_versions(resource) VALUES ('content'),('billing'),('ads'),('companion'),('experiences')
ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION bump_app_config_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE app_config_versions SET revision=revision+1 WHERE resource=TG_ARGV[0];
 RETURN NULL;
END;
$$;
CREATE TRIGGER config_onboarding AFTER INSERT OR UPDATE OR DELETE ON onboarding_configs FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('content');
CREATE TRIGGER config_updates AFTER INSERT OR UPDATE OR DELETE ON whats_new_campaigns FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('content');
CREATE TRIGGER config_social AFTER INSERT OR UPDATE OR DELETE ON social_media_links FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('content');
CREATE TRIGGER config_legal AFTER INSERT OR UPDATE OR DELETE ON legal_documents FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('content');
CREATE TRIGGER config_plans AFTER INSERT OR UPDATE OR DELETE ON subscription_plans FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('billing');
CREATE TRIGGER config_coins AFTER INSERT OR UPDATE OR DELETE ON coin_packs FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('billing');
CREATE TRIGGER config_ads AFTER INSERT OR UPDATE OR DELETE ON admob_settings FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('ads');
CREATE TRIGGER config_portraits AFTER INSERT OR UPDATE OR DELETE ON companion_portraits FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('companion');
CREATE TRIGGER config_agent_options AFTER INSERT OR UPDATE OR DELETE ON agent_settings FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('companion');
CREATE TRIGGER config_experiences AFTER INSERT OR UPDATE OR DELETE ON credit_products FOR EACH STATEMENT EXECUTE FUNCTION bump_app_config_version('experiences');

CREATE INDEX IF NOT EXISTS idx_whats_new_config_start ON whats_new_campaigns(environment,starts_at) WHERE enabled=true AND starts_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_whats_new_config_end ON whats_new_campaigns(environment,ends_at) WHERE enabled=true AND ends_at IS NOT NULL;
