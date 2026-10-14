ALTER TABLE encounter_characters ADD COLUMN age INTEGER NOT NULL DEFAULT 25 CHECK(age BETWEEN 18 AND 100);
ALTER TABLE encounter_characters ADD COLUMN tags JSONB NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(tags)='array' AND jsonb_array_length(tags)<=8);
UPDATE encounter_characters SET age=CASE id::text
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb001' THEN 28
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb002' THEN 30
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb003' THEN 28
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb004' THEN 29 ELSE age END;
UPDATE encounter_characters SET tags=CASE id::text
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb001' THEN '["摄影","爵士"]'::jsonb
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb002' THEN '["旅行","设计"]'::jsonb
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb003' THEN '["时装","艺术"]'::jsonb
 WHEN 'dcfdfec1-9b2b-4a23-93c1-4236d86bb004' THEN '["音乐","旅行"]'::jsonb ELSE tags END;
CREATE TABLE encounter_follows (
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 character_id UUID NOT NULL REFERENCES encounter_characters(id) ON DELETE CASCADE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(user_id,character_id)
);
CREATE INDEX encounter_follow_count ON encounter_follows(character_id);
CREATE TABLE encounter_reports (
 id UUID PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 character_id UUID NOT NULL REFERENCES encounter_characters(id), request_key TEXT NOT NULL,
 reason TEXT NOT NULL, details TEXT NOT NULL, contact TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','valid','dismissed')),
 review_note TEXT NOT NULL DEFAULT '', reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
 reviewed_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(user_id,character_id,request_key)
);
CREATE INDEX encounter_reports_recommendation ON encounter_reports(character_id,user_id,status);
CREATE INDEX encounter_reports_admin ON encounter_reports(created_at DESC);
