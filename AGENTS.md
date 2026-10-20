# Vita repository development guide

This repository is composed of independently built projects. Before changing a
project, read its local guide; the nearest `AGENT.md` takes precedence for that
directory.

## Project index

- [Flutter App](app/AGENTS.md)
- [Go Backend](backend/AGENTS.md)
- [Admin dashboard](admin/AGENTS.md)
- [Web application](webapp/AGENTS.md)
- [Marketing website](website/AGENTS.md)
- [Deployment configuration](deploy/AGENTS.md)

## Repository-wide rules

- Keep Backend, Admin, Webapp and App aligned to the current pre-release API
  contract.
- Do not duplicate shared business rules across clients; enforce authoritative
  rules in Backend and let clients present the returned state.
- Changes to user-visible text must update every locale supported by that
  project and include a translation-key completeness check when practical.
- Run the affected project's tests and static checks before handoff. Do not
  claim device, browser, provider or production verification from build output.
- Never commit, push, stage files or rewrite Git history unless explicitly
  requested.
