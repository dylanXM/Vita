-- Expand the existing constraints without removing legacy platform data.
ALTER TABLE onboarding_configs DROP CONSTRAINT IF EXISTS onboarding_configs_platform_check;
ALTER TABLE onboarding_configs ADD CONSTRAINT onboarding_configs_platform_check
    CHECK (platform IN ('app', 'ios', 'android'));
ALTER TABLE whats_new_campaigns DROP CONSTRAINT IF EXISTS whats_new_campaigns_platform_check;
ALTER TABLE whats_new_campaigns ADD CONSTRAINT whats_new_campaigns_platform_check
    CHECK (platform IN ('app', 'ios', 'android'));

-- iOS is the source for shared onboarding. Legacy rows remain for recovery.
INSERT INTO onboarding_configs (environment, platform, enabled, revision, pages, updated_by, created_at, updated_at)
SELECT environment, 'app', enabled, revision, pages, updated_by, created_at, updated_at
FROM onboarding_configs WHERE platform = 'ios'
ON CONFLICT (environment, platform) DO NOTHING;

-- Existing campaigns keep their IDs and platform provenance. The Backend
-- delivers all app/ios/android campaigns through the shared App scope.
