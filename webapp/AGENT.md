# Web application guide

- Preserve the existing Webapp design system and responsive behavior. Reuse
  shared components and tokens instead of introducing page-local variants.
- Backend remains authoritative for authentication, billing, entitlements and
  generation rules. Handle additive API fields and older responses safely.
- Keep accessibility semantics, keyboard operation, focus states and reduced
  motion intact for interactive components.
- Update all supported locales together when changing visible copy.
- Run the Webapp tests, typecheck, lint and production build after changes.
