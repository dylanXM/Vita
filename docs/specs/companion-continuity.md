# Companion continuity

## Behavior

- Creation selects the initial relationship and closeness. Backend publishes the
  authoritative catalog through `GET /v1/companion-options` (`relationships`).
  The catalog includes girlfriend, boyfriend, wife, husband, crush, confidant,
  family, mentor, colleague, friend, and custom. Each entry supplies allowed
  stages, its default stage, and optional gender/pairing hints.
- Subsequent relationship changes happen in chat. Either party can propose or
  confirm. The memory model must identify explicit agreement by both parties,
  with exact quotes from the latest user statement and adjacent companion
  proposal/acceptance. Unilateral proposals and vague acknowledgements do not
  change the stored relationship. Profile editing preserves the relationship.
- Message count increases familiarity only; it does not advance the relationship
  or automatically create trust/intimacy.
- Memory analysis uses the independent `text_memory` model route. User messages
  are queued transactionally. A worker analyses completed exchanges in order,
  validates structured output, and atomically stores facts and completes the job.
  Provider failures retry with bounded backoff and do not delay chat replies.
- Memories distinguish plans, preferences, boundaries, shared experiences,
  feelings, and outcomes. Corrections retire old facts; reported outcomes or
  cancellations stop pending follow-ups. Date interpretation uses the message's
  timestamp and the user's IANA time zone. Ambiguous dates remain unscheduled.
- Replies, planning, and follow-ups receive character context and active
  continuity. Generated life events remain fictional and grounded in the
  character's recorded timeline; the companion must be truthful about being AI.

## Proactive contact

Admin user details expose account-wide contact preferences. There is no App
contact settings page or relationship confirmation settings page.

`GET/PUT /v1/admin/users/:id/contact-preferences` and
`GET/PUT /v1/me/contact-preferences` share this contract:

```json
{
  "daily_limit": 4,
  "minimum_gap_minutes": 120,
  "quiet_enabled": true,
  "quiet_start": 23,
  "quiet_end": 8
}
```

GET and successful PUT return `{ "preferences": { ... }, "timezone": "..." }`.
All five PUT fields are required. The daily limit is 0–8 (0 disables autonomous
contact); the interval is 30–1440 minutes. Quiet hours use local whole hours,
support crossing midnight, and require distinct start/end when enabled.

Life shares and memory follow-ups share the account's limit and interval across
all companions. The global daily limit remains a hard cap; enthusiasm cannot
bypass it. Recent chatting/visiting suppresses autonomous contact. A final check
under a user-row lock prevents concurrent workers exceeding the budget. Pending
memory analysis postpones follow-ups so new outcomes and boundaries are applied
before delivery.

## Activation and verification

1. Apply `backend/migrations/20261012_companion_continuity.sql` before starting
   the new Backend. Ship Backend and Admin together, then App.
2. In Admin Model services, enable a text model for Conversation memory. In
   Model routing, select its primary/fallback models and enable `text_memory`.
   This route starts disabled and adds model invocation cost when enabled.
3. Create a family or mentor character; verify its creation form excludes the
   partner stage. Create a spouse character; verify the partner stage is selected.
4. In chat, mention tomorrow's interview and a boundary. After analysis completes,
   return to chat and verify specific continuity. Report the interview result;
   verify its old memory is resolved and its follow-up timestamp cleared.
5. Exercise user-led and companion-led relationship proposals. Verify unilateral
   proposals leave the stored relationship unchanged and mutual agreements update
   both type and stage. This needs a real model evaluation; mock tests verify the
   persistence and evidence-validation mechanics, not model judgement quality.
6. In Admin, set daily contact to 0, then test a low limit/quiet interval. Verify
   both Life shares and memory follow-ups respect it across companions.

Deterministic PostgreSQL integration tests use only an explicitly named
disposable database. `TestCompanionContinuityPostgres` accepts
`VITA_CONTINUITY_TEST_DSN` only when its database name starts with
`vita_continuity_test_`, resets that database's public schema, and tests memory
correction, retries, mutual consent, and concurrent contact limits. Never point
this test at an application database.

## Changed files

- Backend behavior: `backend/internal/agent/service.go`, `memory.go`,
  `contact_preferences.go`, `model_validation.go`;
  `backend/internal/companion/relationships.go`.
- Backend APIs: `backend/cmd/server/main.go`;
  `backend/internal/handler/handler.go`, `agent.go`,
  `contact_preferences.go`, `companion_relationship.go`, `companion_story.go`.
- Database: `backend/migrations/20261012_companion_continuity.sql`.
- Backend tests: `backend/internal/agent/memory_test.go`,
  `continuity_integration_test.go`, `model_validation_test.go`;
  `backend/internal/companion/relationships_test.go`;
  `backend/internal/handler/agent_media_routes_test.go`.
- Admin: `admin/src/pages/UserContactPreferences.tsx`, `UserDetailPage.tsx`,
  `CompanionDetailPage.tsx`, `ModelServicesPage.tsx`;
  `admin/src/api/admin.ts`, `types.ts`;
  `admin/src/i18n/locales/en.ts`, `zh-Hans.ts`, `locales.test.ts`.
- App: `app/lib/features/companion/companion_create_page.dart`,
  `companion_create_method_page.dart`, `companion_relation_rules.dart`;
  `app/lib/core/i18n/translations.dart`, `additional_translations.dart`;
  `app/test/companion_relationship_options_test.dart`.
- Documentation: `docs/specs/companion-continuity.md`.
