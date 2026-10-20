# Admin dashboard guide

- Admin is an operational dashboard, not a consumer marketing surface. Use the
  existing compact cards, tables, page headers and form controls consistently.
- Every setting must map to a Backend-owned contract. Do not create UI-only
  configuration that the Backend cannot store or enforce.
- Destructive actions need explicit confirmation. Prevent deletion of providers
  or models that remain referenced by active configuration.
- Model-routing forms must distinguish behavior enablement, one default model
  and ordered unique fallback models, filtered by enabled capability.
- Update every locale file when adding keys and keep their key sets aligned.
- Run Vitest, `tsc -b` and the Vite production build after changes.
