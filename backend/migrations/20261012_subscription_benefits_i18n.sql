ALTER TABLE subscription_plans ADD COLUMN IF NOT EXISTS benefits_i18n JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE subscription_plans ADD CONSTRAINT subscription_benefits_i18n_object CHECK(jsonb_typeof(benefits_i18n)='object');
