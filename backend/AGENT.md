# Go Backend guide

- Backend is the authority for billing, entitlements, credit charging, model
  routing and character behavior. Clients must not reproduce these decisions.
- Keep API responses aligned to the current pre-release App contract. Deploy
  migrations before code that requires them.
- Validate all Admin input at the API boundary. Media routes require an enabled
  default model for the selected route when active and preserve ordered, unique fallbacks.
- Keep database writes for charging and fulfillment transactional or provide a
  confirmed refund path.
- Format touched Go files with `gofmt`, then run `go test ./...` and
  `go vet ./...`. Provider behavior should use deterministic `httptest` tests;
  database-specific behavior should be verified against PostgreSQL when added.
