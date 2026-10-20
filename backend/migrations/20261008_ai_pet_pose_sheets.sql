ALTER TABLE ai_pet_breeds
    ADD COLUMN IF NOT EXISTS sprite_sheet_url TEXT NOT NULL DEFAULT '';
ALTER TABLE ai_pet_breeds
    ADD COLUMN IF NOT EXISTS action_sheet_url TEXT NOT NULL DEFAULT '';

UPDATE ai_pet_breeds
SET sprite_sheet_url = replace(avatar_url, '.png', '_poses.png')
WHERE sprite_sheet_url = ''
  AND avatar_url IN (
    'asset://assets/ai_pets/cat_orange.png',
    'asset://assets/ai_pets/cat_tuxedo.png',
    'asset://assets/ai_pets/cat_ragdoll.png',
    'asset://assets/ai_pets/dog_corgi.png',
    'asset://assets/ai_pets/dog_shiba.png',
    'asset://assets/ai_pets/dog_retriever.png'
  );

UPDATE ai_pet_breeds
SET action_sheet_url = replace(avatar_url, '.png', '_actions.png')
WHERE action_sheet_url = ''
  AND avatar_url IN (
    'asset://assets/ai_pets/cat_orange.png',
    'asset://assets/ai_pets/cat_tuxedo.png',
    'asset://assets/ai_pets/cat_ragdoll.png',
    'asset://assets/ai_pets/dog_corgi.png',
    'asset://assets/ai_pets/dog_shiba.png',
    'asset://assets/ai_pets/dog_retriever.png'
  );
