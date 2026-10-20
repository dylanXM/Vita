Kie rollout:
1. Apply 20261011_kie_provider.sql before deploying Backend + Admin.
2. Set VITA_PUBLIC_API_BASE_URL to the public HTTPS Backend origin (no path).
   Submitted tasks receive callBackUrl = <origin>/v1/providers/kie/callback.
3. Ensure the public reverse proxy allows POST to that endpoint without login.
4. Configure the KIE service address as https://api.kie.ai and test the model.

Callbacks wake active jobs; results are verified through Kie's recordInfo API.
Polling remains the fallback when callbacks arrive early, are lost, or hit another
Backend instance. Callback bodies never directly fulfill jobs or change balances.
No App update is required. This migration extends the provider constraint and
retains existing providers. Real Kie callbacks and PostgreSQL migration execution
must be verified in the deployment environment.
