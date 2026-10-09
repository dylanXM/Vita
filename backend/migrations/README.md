# Production schema changes

The backend release script backs up PostgreSQL, then runs `/app/migrate` from
the new backend image before restarting the API. The migration command first
applies the historical idempotent schema in `internal/db/db.go`, then applies
new `.sql` files in this directory in filename order. SQL files are embedded in
the binary at build time.

The existing files through `20261009_ai_pet_care.sql` are historical and are
not replayed; the inline schema continues to handle those changes. Put future
database changes in a **new, uniquely named** `.sql` file that sorts after that
name. Do not edit a file after it has run in production: its SHA-256 checksum is
recorded in `schema_migrations`, and a changed file stops the next release.
Each file runs in one transaction; do not include `BEGIN` or `COMMIT` in new
files. Keep migrations additive so the previous backend image remains usable
if the new API fails its health check. Database rollback is a separate manual
operation; the release script only rolls back the API image.
