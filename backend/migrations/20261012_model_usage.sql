CREATE TABLE IF NOT EXISTS ai_model_rates (
 model_id TEXT PRIMARY KEY REFERENCES ai_models(id) ON DELETE CASCADE,
 unit TEXT NOT NULL DEFAULT 'tokens' CHECK (unit IN ('tokens','call')),
 input_usd NUMERIC CHECK(input_usd >= 0), output_usd NUMERIC CHECK(output_usd >= 0),
 cache_read_usd NUMERIC CHECK(cache_read_usd >= 0), cache_write_usd NUMERIC CHECK(cache_write_usd >= 0),
 call_usd NUMERIC CHECK(call_usd >= 0), updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS model_calls (
 id TEXT PRIMARY KEY, model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
 model_name TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
 request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT NOT NULL,
 input_tokens BIGINT NOT NULL, output_tokens BIGINT NOT NULL, cache_read_tokens BIGINT NOT NULL,
 cache_write_tokens BIGINT NOT NULL, usage_known BOOLEAN NOT NULL, rates JSONB NOT NULL,
 estimated_cost_usd NUMERIC, started_at TIMESTAMPTZ NOT NULL, finished_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS model_calls_model_time ON model_calls(model_id,started_at DESC,id);
CREATE INDEX IF NOT EXISTS model_calls_time ON model_calls(started_at DESC);
