-- New accounts receive their trial atomically with account creation.
CREATE OR REPLACE FUNCTION start_registration_companion_trial()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO default_companion_trials(user_id, started_at, expires_at)
    SELECT NEW.id, NEW.created_at,
           NEW.created_at + GREATEST(free_default_chat_hours, 1) * INTERVAL '1 hour'
    FROM agent_settings WHERE id = 'default';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'default agent settings required for registration trial';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER users_registration_companion_trial
AFTER INSERT ON users
FOR EACH ROW EXECUTE FUNCTION start_registration_companion_trial();

-- Existing accounts also count from registration, including unused trials.
INSERT INTO default_companion_trials(user_id, started_at, expires_at)
SELECT u.id, u.created_at,
       u.created_at + GREATEST(s.free_default_chat_hours, 1) * INTERVAL '1 hour'
FROM users u CROSS JOIN agent_settings s WHERE s.id = 'default'
ON CONFLICT(user_id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    expires_at = EXCLUDED.expires_at;
