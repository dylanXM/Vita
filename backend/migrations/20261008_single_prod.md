# Single production content scope

The database keeps its legacy `environment` columns, while application content
uses only `prod`. Run the migration before starting the updated backend.

1. Back up the PostgreSQL database and pause writes from old backend instances.
2. If legacy R2/COS media exists, run `go run ./cmd/migrate_env_media` from
   `backend` with `VITA_DB_DSN` and `VITA_AGENT_CONFIG_KEY` set. It copies
   each live object to the configured prod provider, updates its row after a
   successful upload, and drains the legacy deletion queues. Old objects are
   retained for recovery.
3. Run `go run ./cmd/migrate` from `backend`. This applies schema changes and
   migrates business records in one transaction. Prod configuration wins;
   legacy singleton and same-key configuration rows are preserved as JSON in
   `legacy_environment_archive`. Referenced subscription plans keep their IDs
   and receive unique legacy keys. Duplicate store product IDs resolve to the
   prod plan.
4. Confirm all `environment` and `storage_environment` values in live tables
   are `prod`, then start backend, Admin, and webapp. The App can follow later.

The database migration refuses to relabel external media or pending deletions
while they still point at a legacy storage scope. Do not bypass that check by
editing the marker columns directly: that would make existing media unreadable.
