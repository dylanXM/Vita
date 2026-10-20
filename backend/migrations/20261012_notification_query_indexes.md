# Notification polling

Apply the additive indexes before deploying Backend; deploy Admin/Webapp with
Backend as usual, then the App. Existing companion-list clients remain supported.

Authenticated GET /v1/companions/updates accepts an optional opaque `cursor`.
It returns `{items, removed_ids, cursor}`. Items contain only changed companion
message summaries: id, last_message, last_message_type, last_message_at and
unread_count. An unchanged poll returns empty arrays. The initial poll returns
all summaries. Every database lookup is scoped to the authenticated user.
The cursor is an untrusted snapshot, not permission to access another account.

App polls every 10 seconds only while signed in and resumed. A full list refresh
occurs on foreground resume, manual/operation-driven refresh, or an unknown
companion in a delta. Logout invalidates in-flight responses and clears cursors.
Push can later call the same delta refresh; this release does not add push.

Validation still required: authenticated initial/delta/unchanged/removal polls,
read-receipt transitions to unread_count=0, logout/login and foreground lifecycle,
and real API p50/p95 latency. [SLOW_API] records requests >=100ms, plus process-wide
pool-wait deltas; those deltas cannot be attributed to one request's SQL.
No tests, builds, migration execution or production latency measurements were run.
