-- Add a new experience; do not repurpose existing movie bookings.
INSERT INTO credit_products(environment,product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata,subscription_only,is_launched)
VALUES('prod','date_dance','date','experience.date.dance','experience.date.dance.desc','',150,false,35,'{"duration_minutes":60,"location":"ballroom"}'::jsonb,false,false)
ON CONFLICT(environment,product_key) DO NOTHING;
