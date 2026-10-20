INSERT INTO subscription_plans
    (id,key,name,environment,platform,coins_granted,price_usd,period,product_id,enabled,sort_order)
SELECT 'catalog-' || env || '-' || platform || '-' || key,key,name,env,platform,coins,price,period,product_id,true,sort_order
FROM (VALUES
    ('plus_monthly','Vita Plus Monthly',500,9.99::numeric,'month','vita.plus.monthly',10),
    ('plus_yearly','Vita Plus Yearly',500,79.99::numeric,'year','vita.plus.yearly',20),
    ('premium_monthly','Vita Premium Monthly',1200,19.99::numeric,'month','vita.premium.monthly',30),
    ('premium_yearly','Vita Premium Yearly',1200,159.99::numeric,'year','vita.premium.yearly',40)
) AS products(key,name,coins,price,period,product_id,sort_order)
CROSS JOIN (VALUES('dev'),('beta'),('prod')) AS environments(env)
CROSS JOIN (VALUES('ios'),('android')) AS platforms(platform)
ON CONFLICT(environment,platform,key) DO UPDATE SET
    name=EXCLUDED.name,coins_granted=EXCLUDED.coins_granted,price_usd=EXCLUDED.price_usd,
    period=EXCLUDED.period,product_id=EXCLUDED.product_id,sort_order=EXCLUDED.sort_order;

CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_transactions_annual_subscription_month
    ON credit_transactions(user_id,description)
    WHERE description LIKE 'annual-subscription-month:%';

INSERT INTO coin_packs
    (id,key,name,environment,platform,coins,price_usd,product_id,popular,enabled,sort_order)
SELECT 'catalog-' || env || '-' || platform || '-' || key,key,name,env,platform,coins,price,product_id,popular,true,sort_order
FROM (VALUES
    ('coins_100','100 Coins',100,1.99::numeric,'vita.coins.100',false,10),
    ('coins_500','500 Coins',500,7.99::numeric,'vita.coins.500',true,20),
    ('coins_1200','1,200 Coins',1200,14.99::numeric,'vita.coins.1200',false,30)
) AS products(key,name,coins,price,product_id,popular,sort_order)
CROSS JOIN (VALUES('dev'),('beta'),('prod')) AS environments(env)
CROSS JOIN (VALUES('ios'),('android')) AS platforms(platform)
ON CONFLICT(environment,platform,key) DO UPDATE SET product_id=EXCLUDED.product_id;
