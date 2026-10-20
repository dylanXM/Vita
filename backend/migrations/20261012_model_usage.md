# Model usage and Life Plan timeout rollout

Additive schema: `ai_model_rates` stores configurable supplier USD rates;
`model_calls` stores provider interaction summaries, reported token usage, rate
snapshots and nullable estimated cost. The same idempotent statements are in
`internal/db/db.go`, which is the production `cmd/migrate` entry point.

Apply migration before Backend, then deploy Admin and Webapp together using the
existing release workflow. App stays compatible and can ship later. No API fields
are removed. Rollback code without dropping the new tables or deleting history.

Life Plan provider timeout is 120 seconds per call, with caller cancellation
preserved; normal chat remains 45 seconds. Admin trigger-plan has a 600-second
batch budget, Backend response/Admin nginx allow 650 seconds, Admin client allows
660 seconds. Proactive deadlines remain unchanged. External proxies, if present,
must also allow this route's response budget.

Provider connection tests for KIE use the documented GET `/api/v1/chat/credit`
API and verify HTTP success, JSON `code=200`, and a returned balance. A zero balance
is still a valid connection; business errors returned with HTTP 200 are failures.

Estimated cost covers registered-model calls captured after deployment, including
runtime calls and saved-model scenario tests. Before registration, model creation
validation has no saved model ID and is not attributed to a model. Connectivity
checks do not generate model calls. Legacy agent_runs are displayed separately;
they lack usage/rate data and cannot be retrospectively priced. Summaries are
limited to 16,000 characters and do not store API keys or audio binaries.

Text pricing uses reported uncached input/output/cache-read/cache-write token
counts multiplied by their USD/million rates. Media can use USD/successful call.
Missing usage/rates and unknown failure outcomes stay unpriced, not zero. Token
usage returned on a failed/truncated response is still priced if rates are known.
Rate changes only affect later calls; historical prices use their recorded snapshot.
Dashboard today uses Asia/Shanghai. These are estimates, not supplier invoices.

Fastest runtime verification after release:
1. Retest KIE connection with the saved provider, including valid/invalid keys.
2. Set one saved model's supplier rates in Model services → Details.
3. Run a real chat or Life Plan and inspect the call's request/response, token
   usage and rate snapshot; verify its cost equals tokens × rate / 1,000,000.
4. Compare model and dashboard today/cumulative totals. A model with unconfigured
   rates should increment unpriced calls, not create an estimated zero-cost call.
5. Run Life Plan with an upstream response taking longer than 45 seconds; check
   completion and failure cleanup from the actual Admin flow.

No resource-intensive tests, builds or provider calls were run during this change.
Go regression cases were added/updated but remain unexecuted under project rules.
