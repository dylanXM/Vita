CREATE TABLE IF NOT EXISTS story_settings (
  environment TEXT PRIMARY KEY CHECK (environment IN ('dev','beta','prod')),
  free_chapter_limit INTEGER NOT NULL DEFAULT 3 CHECK (free_chapter_limit >= 0),
  custom_background_limit INTEGER NOT NULL DEFAULT 3 CHECK (custom_background_limit >= 0),
  storyboard_unlock_chapters INTEGER NOT NULL DEFAULT 8 CHECK (storyboard_unlock_chapters > 0),
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO story_settings(environment) VALUES('dev'),('beta'),('prod') ON CONFLICT(environment) DO NOTHING;

CREATE TABLE IF NOT EXISTS story_backgrounds (
  id TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('dev','beta','prod')),
  owner_user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  cover_url TEXT NOT NULL DEFAULT '',
  synopsis TEXT NOT NULL DEFAULT '',
  world_setting TEXT NOT NULL,
  opening TEXT NOT NULL,
  genre TEXT NOT NULL DEFAULT '',
  character_constraints TEXT NOT NULL DEFAULT '',
  story_goal TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  enabled BOOLEAN NOT NULL DEFAULT true,
  deleted_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_story_backgrounds_catalog ON story_backgrounds(environment,owner_user_id,enabled,sort_order);
CREATE INDEX IF NOT EXISTS idx_story_backgrounds_owner_quota ON story_backgrounds(owner_user_id,created_at);

INSERT INTO story_backgrounds(id,environment,title,synopsis,world_setting,opening,genre,character_constraints,sort_order)
SELECT 'story-default-moon-train-'||env,env,'月夜列车','一列只在月圆之夜出现的列车，载着未说出口的愿望。','现代城市与梦境交界；列车每站都通向一段被遗忘的往事。','你和 TA 在空无一人的月台登上末班列车，车票背面写着一个陌生人的名字。','奇幻','主角必须由用户选择的角色担任，保持角色原有人设。',10
FROM (VALUES('dev'),('beta'),('prod')) environments(env) ON CONFLICT(id) DO NOTHING;
INSERT INTO story_backgrounds(id,environment,title,synopsis,world_setting,opening,genre,character_constraints,sort_order)
SELECT 'story-default-seaside-'||env,env,'潮汐来信','海边小镇每天退潮后都会留下来自未来的信。','安静的海滨小镇；潮汐会改变时间留下的痕迹。','你和 TA 在清晨的沙滩捡到一封落款是十年后的信，信中警告今天不要去灯塔。','治愈悬疑','主角必须由用户选择的角色担任，保持角色原有人设。',20
FROM (VALUES('dev'),('beta'),('prod')) environments(env) ON CONFLICT(id) DO NOTHING;
INSERT INTO story_backgrounds(id,environment,title,synopsis,world_setting,opening,genre,character_constraints,sort_order)
SELECT 'story-default-bookshop-'||env,env,'旧书店的第十三层','旧书店不存在的楼层收藏着尚未发生的故事。','城市旧街区；书页中的故事会短暂映照现实。','打烊后，TA 发现书架后多出一段向上的楼梯，而楼上有人正在读一本写着你们名字的书。','都市奇谈','主角必须由用户选择的角色担任，保持角色原有人设。',30
FROM (VALUES('dev'),('beta'),('prod')) environments(env) ON CONFLICT(id) DO NOTHING;

CREATE TABLE IF NOT EXISTS stories (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
  background_id TEXT REFERENCES story_backgrounds(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  background_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  current_chapter_no INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed')),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id,updated_at DESC);

CREATE TABLE IF NOT EXISTS story_chapters (
  id TEXT PRIMARY KEY,
  story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  chapter_no INTEGER NOT NULL CHECK (chapter_no > 0),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  choices JSONB NOT NULL DEFAULT '[]'::jsonb,
  selected_choice_id TEXT NOT NULL DEFAULT '',
  selected_choice_text TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(story_id,chapter_no)
);

CREATE TABLE IF NOT EXISTS storyboards (
  id TEXT PRIMARY KEY,
  story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','generating','completed','failed')),
  summary TEXT NOT NULL DEFAULT '',
  image_url TEXT NOT NULL DEFAULT '',
  panel_count INTEGER NOT NULL CHECK (panel_count IN (4,6,8,9)),
  panels JSONB NOT NULL DEFAULT '[]'::jsonb,
  spend_id TEXT,
  failure_reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE storyboards ADD COLUMN IF NOT EXISTS image_url TEXT NOT NULL DEFAULT '';
ALTER TABLE storyboards ADD COLUMN IF NOT EXISTS panel_count INTEGER NOT NULL DEFAULT 8;
ALTER TABLE storyboards DROP CONSTRAINT IF EXISTS storyboards_status_check;
ALTER TABLE storyboards ADD CONSTRAINT storyboards_status_check CHECK (status IN ('pending','generating','completed','failed'));
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='storyboards_panel_count_check') THEN
    ALTER TABLE storyboards ADD CONSTRAINT storyboards_panel_count_check CHECK (panel_count IN (4,6,8,9));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_storyboards_story ON storyboards(story_id,created_at DESC);

ALTER TABLE credit_products DROP CONSTRAINT IF EXISTS credit_products_category_check;
ALTER TABLE credit_products ADD CONSTRAINT credit_products_category_check
  CHECK (category IN ('gift','photo','voice','date','keepsake','outfit','call','pet','story'));
INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
SELECT env,'story_chapter','story','credits.product.storyChapter.name','credits.product.storyChapter.description','📖',10,true,10,'{"hidden_from_catalog":true}'::jsonb
FROM (VALUES('dev'),('beta'),('prod')) environments(env) ON CONFLICT(environment,product_key) DO NOTHING;
INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata)
SELECT env,'story_storyboard','story','credits.product.storyboard.name','credits.product.storyboard.description','🎞️',80,true,20,'{"hidden_from_catalog":true}'::jsonb
FROM (VALUES('dev'),('beta'),('prod')) environments(env) ON CONFLICT(environment,product_key) DO NOTHING;

INSERT INTO agent_media_routes(route_key,media_type,enabled,fallback_model_ids)
VALUES ('text_story_chapter','text',false,'[]'::jsonb),('text_storyboard','text',false,'[]'::jsonb),('image_storyboard_sheet','image',false,'[]'::jsonb)
ON CONFLICT(route_key) DO NOTHING;
UPDATE agent_media_routes target SET primary_model_id=source.primary_model_id,fallback_model_ids=source.fallback_model_ids,enabled=source.enabled
FROM agent_media_routes source WHERE source.route_key='text_chat' AND target.route_key IN ('text_story_chapter','text_storyboard') AND target.primary_model_id IS NULL;
UPDATE agent_media_routes target SET primary_model_id=source.primary_model_id,fallback_model_ids=source.fallback_model_ids,enabled=source.enabled
FROM agent_media_routes source WHERE source.route_key='image_requested_photo' AND target.route_key='image_storyboard_sheet' AND target.primary_model_id IS NULL;
UPDATE ai_models SET configured_scenarios = configured_scenarios || '["text_story_chapter"]'::jsonb
WHERE capabilities ? 'text' AND NOT configured_scenarios ? 'text_story_chapter';
UPDATE ai_models SET configured_scenarios = configured_scenarios || '["text_storyboard"]'::jsonb
WHERE capabilities ? 'text' AND NOT configured_scenarios ? 'text_storyboard';
UPDATE ai_models SET configured_scenarios = configured_scenarios || '["image_storyboard_sheet"]'::jsonb
WHERE capabilities ? 'image' AND NOT configured_scenarios ? 'image_storyboard_sheet';
