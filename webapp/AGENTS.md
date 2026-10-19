# Web application guide

- Preserve the existing Webapp design system and responsive behavior. Reuse
  shared components and tokens instead of introducing page-local variants.
- Backend remains authoritative for authentication, billing, entitlements and
  generation rules. Handle additive API fields and older responses safely.
- Keep accessibility semantics, keyboard operation, focus states and reduced
  motion intact for interactive components.
- Update all supported locales together when changing visible copy.
- Run the Webapp tests, typecheck, lint and production build after changes.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
