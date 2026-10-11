ALTER TABLE credit_products ADD COLUMN IF NOT EXISTS subscription_only BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE credit_products ADD COLUMN IF NOT EXISTS is_launched BOOLEAN NOT NULL DEFAULT true;

-- Preserve the subscription requirement for existing companion experiences.
UPDATE credit_products SET subscription_only=true
WHERE category IN ('gift','photo','voice','date','keepsake','outfit','call');
-- Real-time calls are not implemented; they must not be purchasable.
UPDATE credit_products SET is_launched=false WHERE category='call';
