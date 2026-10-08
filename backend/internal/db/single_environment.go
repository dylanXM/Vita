package db

import (
	"database/sql"
	"fmt"
)

// migrateSingleEnvironment folds legacy content into the one supported business
// environment. The transaction deliberately stops before changing references
// to external objects: their bytes must be copied to the prod bucket first.
func migrateSingleEnvironment(database *sql.DB) error {
	tx, err := database.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var externalObjects int
	if err := tx.QueryRow(`SELECT
		(SELECT COUNT(*) FROM media_assets WHERE storage_environment<>'prod' AND storage_provider IN ('r2','cos'))+
		(SELECT COUNT(*) FROM admin_images WHERE storage_environment<>'prod' AND storage_provider IN ('r2','cos'))+
		(SELECT COUNT(*) FROM media_object_deletions WHERE environment<>'prod')`).Scan(&externalObjects); err != nil {
		return fmt.Errorf("inspect legacy media: %w", err)
	}
	if externalObjects != 0 {
		return fmt.Errorf("single-environment migration requires copying %d legacy external media objects/deletions to prod storage before relabeling", externalObjects)
	}

	queries := []string{
		`CREATE TABLE IF NOT EXISTS legacy_environment_archive (
			id BIGSERIAL PRIMARY KEY,
			table_name TEXT NOT NULL,
			original_environment TEXT NOT NULL,
			row_data JSONB NOT NULL,
			archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		// Keep live prod configuration. Legacy singleton and same-key rows are
		// archived in full before removal; transaction history remains in place.
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'legal_documents',environment,to_jsonb(t) FROM legal_documents t WHERE environment<>'prod'`,
		`DELETE FROM legal_documents WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'credit_products',environment,to_jsonb(t) FROM credit_products t WHERE environment<>'prod'`,
		`DELETE FROM credit_products WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'invitation_settings',environment,to_jsonb(t) FROM invitation_settings t WHERE environment<>'prod'`,
		`DELETE FROM invitation_settings WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'media_storage_settings',environment,to_jsonb(t) FROM media_storage_settings t WHERE environment<>'prod'`,
		`DELETE FROM media_storage_settings WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'media_storage_configs',environment,to_jsonb(t) FROM media_storage_configs t WHERE environment<>'prod'`,
		`DELETE FROM media_storage_configs WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'onboarding_configs',environment,to_jsonb(t) FROM onboarding_configs t WHERE environment<>'prod'`,
		`DELETE FROM onboarding_configs WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'social_media_links',environment,to_jsonb(t) FROM social_media_links t WHERE environment<>'prod'`,
		`DELETE FROM social_media_links WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'story_settings',environment,to_jsonb(t) FROM story_settings t WHERE environment<>'prod'`,
		`DELETE FROM story_settings WHERE environment<>'prod'`,
		`INSERT INTO legacy_environment_archive(table_name,original_environment,row_data)
			SELECT 'world_places',environment,to_jsonb(t) FROM world_places t WHERE environment<>'prod'`,
		`DELETE FROM world_places WHERE environment<>'prod'`,
		// Referenced plans keep their IDs. A prod plan always wins a duplicate
		// store product ID, so existing subscriptions can resolve through it.
		`UPDATE subscription_plans SET key='legacy-'||id WHERE environment<>'prod'`,
		`WITH ranked AS (
			SELECT id,ROW_NUMBER() OVER (PARTITION BY platform,product_id ORDER BY CASE WHEN environment='prod' THEN 0 ELSE 1 END,id) AS position
			FROM subscription_plans WHERE product_id<>''
		) UPDATE subscription_plans p SET product_id='',enabled=false FROM ranked r WHERE p.id=r.id AND r.position>1`,
		`UPDATE subscription_plans SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE coin_packs SET key='legacy-'||id WHERE environment<>'prod'`,
		`WITH ranked AS (
			SELECT id,ROW_NUMBER() OVER (PARTITION BY platform,product_id ORDER BY CASE WHEN environment='prod' THEN 0 ELSE 1 END,id) AS position
			FROM coin_packs WHERE product_id<>''
		) UPDATE coin_packs p SET product_id='',enabled=false FROM ranked r WHERE p.id=r.id AND r.position>1`,
		`UPDATE coin_packs SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE ai_pet_breeds SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE story_backgrounds SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE whats_new_campaigns SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE world_campaigns SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE users SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE credit_transactions SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE subscriptions SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE billing_purchases SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE admin_grant_operations SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE analytics_events SET environment='prod' WHERE environment<>'prod'`,
		`UPDATE media_assets SET storage_environment='prod' WHERE storage_environment<>'prod'`,
		`UPDATE admin_images SET storage_environment='prod' WHERE storage_environment<>'prod'`,
		`DO $$ DECLARE column_record RECORD; remaining BIGINT;
		BEGIN
			FOR column_record IN SELECT table_name,column_name FROM information_schema.columns
				WHERE table_schema='public' AND column_name IN ('environment','storage_environment')
			LOOP
				EXECUTE format('SELECT COUNT(*) FROM %I WHERE %I<>$1',column_record.table_name,column_record.column_name)
				INTO remaining USING 'prod';
				IF remaining<>0 THEN
					RAISE EXCEPTION 'legacy environment values remain in %.%',column_record.table_name,column_record.column_name;
				END IF;
			END LOOP;
		END $$`,
	}
	for _, query := range queries {
		if _, err := tx.Exec(query); err != nil {
			return fmt.Errorf("single-environment migration step failed: %w", err)
		}
	}
	return tx.Commit()
}
