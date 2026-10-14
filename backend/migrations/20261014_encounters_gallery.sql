ALTER TABLE encounter_characters ADD COLUMN image_urls JSONB NOT NULL DEFAULT '[]'::jsonb;
UPDATE encounter_characters SET image_urls=jsonb_build_array(cover_url);
-- Preserve old Backend/clients that insert or update only cover_url during rollout.
CREATE FUNCTION normalize_encounter_gallery() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.image_urls='[]'::jsonb THEN
  NEW.image_urls=jsonb_build_array(NEW.cover_url);
 ELSIF TG_OP='UPDATE' THEN
  IF NEW.image_urls=OLD.image_urls AND NEW.cover_url IS DISTINCT FROM OLD.cover_url THEN
   NEW.image_urls=jsonb_set(NEW.image_urls,'{0}',to_jsonb(NEW.cover_url));
  END IF;
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER normalize_encounter_gallery BEFORE INSERT OR UPDATE ON encounter_characters
FOR EACH ROW EXECUTE FUNCTION normalize_encounter_gallery();
ALTER TABLE encounter_characters ADD CONSTRAINT encounter_images_limit CHECK (jsonb_typeof(image_urls)='array' AND jsonb_array_length(image_urls) BETWEEN 1 AND 3 AND (image_urls->>0)=cover_url);
