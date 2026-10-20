CREATE TABLE IF NOT EXISTS ai_model_subscription_plans (
    model_id TEXT NOT NULL REFERENCES ai_models(id) ON DELETE CASCADE,
    subscription_plan_id TEXT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(model_id, subscription_plan_id)
);

CREATE INDEX IF NOT EXISTS idx_ai_model_subscription_plans_plan
    ON ai_model_subscription_plans(subscription_plan_id, model_id);
