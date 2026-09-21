# Deployment guide

- Backend, Admin, Webapp and App target the same current pre-release API
  contract.
- Apply additive database migrations before starting Backend code that reads the
  new schema. Do not enable destructive schema changes in the same rollout.
- Keep dev, beta and prod environment values isolated. Never copy secrets into
  tracked example files or logs.
- Validate Compose rendering and service health before production rollout.
  Document the exact migration and rollback order for behavior-changing work.
