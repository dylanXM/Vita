-- Persistent claim survives companion deletion and purge.
ALTER TABLE users ADD COLUMN IF NOT EXISTS free_companion_claimed boolean NOT NULL DEFAULT false;
ALTER TABLE companions ADD COLUMN IF NOT EXISTS free_trial_companion boolean NOT NULL DEFAULT false;
-- Existing personal companions count toward the lifetime allowance.
UPDATE users u SET free_companion_claimed=true WHERE EXISTS (
 SELECT 1 FROM companions c WHERE c.user_id=u.id AND c.is_default=false
 AND c.pet_breed_id IS NULL AND COALESCE(c.creation_source,'')<>'ai_pet');
UPDATE companions SET free_trial_companion=true WHERE id IN (
 SELECT DISTINCT ON (user_id) id FROM companions WHERE is_default=false
 AND pet_breed_id IS NULL AND COALESCE(creation_source,'')<>'ai_pet'
 ORDER BY user_id,created_at,id);
UPDATE agent_settings SET free_default_chat_hours=12 WHERE id='default';
CREATE OR REPLACE FUNCTION start_registration_companion_trial()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO default_companion_trials(user_id,started_at,expires_at)
 VALUES(NEW.id,NEW.created_at,NEW.created_at + INTERVAL '12 hours');
 RETURN NEW;
END;
$$;
INSERT INTO default_companion_trials(user_id,started_at,expires_at)
SELECT id,created_at,created_at + INTERVAL '12 hours' FROM users
ON CONFLICT(user_id) DO UPDATE SET started_at=EXCLUDED.started_at,expires_at=EXCLUDED.expires_at;
CREATE OR REPLACE FUNCTION vita_companion_access(p_user_id text,p_companion_id text)
RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=p_user_id AND s.status='active'
 AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP))
 OR EXISTS(SELECT 1 FROM companions c JOIN users u ON u.id=c.user_id
 WHERE c.id=p_companion_id AND c.user_id=p_user_id AND c.deleted_at IS NULL
 AND (c.is_default OR c.free_trial_companion) AND u.created_at + INTERVAL '12 hours'>CURRENT_TIMESTAMP);
$$;
UPDATE companions c SET life_enabled=true,friendship_active=true,subscription_paused_at=NULL
WHERE c.free_trial_companion AND c.active AND c.deleted_at IS NULL AND vita_companion_access(c.user_id,c.id);
