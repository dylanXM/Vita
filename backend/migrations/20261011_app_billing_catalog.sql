-- Destructive catalog reset requested: keep Web products and purchase history.
DELETE FROM subscription_plans WHERE platform IN ('ios','android');
DELETE FROM coin_packs WHERE platform IN ('ios','android');
ALTER TABLE subscription_plans DROP CONSTRAINT IF EXISTS subscription_plans_platform_check;
ALTER TABLE subscription_plans ADD CONSTRAINT subscription_plans_platform_check CHECK(platform IN ('app','web'));
ALTER TABLE coin_packs DROP CONSTRAINT IF EXISTS coin_packs_platform_check;
ALTER TABLE coin_packs ADD CONSTRAINT coin_packs_platform_check CHECK(platform IN ('app','web'));
