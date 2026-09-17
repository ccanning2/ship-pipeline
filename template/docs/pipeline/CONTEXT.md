# __PROJECT_NAME__ — Pipeline context (read by every persona)

The personas are generic; THIS file is what makes them behave correctly for this project. Keep it current — the product owner owns it.

## Product
- What it is, for whom, and how it's positioned (one paragraph).
- Brand: name, tagline, palette, tone. Claims that must NOT be made.
- User segments / roles: <e.g. customer, vendor, admin>.
- Marketing channels: <e.g. Instagram, LinkedIn, WhatsApp broadcast, in-app>.

## Market
- Competitors to track: <list>.
- Where real customer signal lives: <forums, review sites, social>.
- Regulatory notes: <data protection, payments, sector rules>.

## Stack & commands
- Backend: <framework, language, version>. Frontend: <framework>. Database: <db>.
- Backend tests: `<command>` (baseline: <n> tests — must never drop).
- Frontend tests: `<command>`. Lint/build: `<command>`.
- Docker: `<Dockerfile path>`; image: `ghcr.io/<owner>/<repo>:<sha>` (also tagged `:vX.Y.Z` in production).
- Architecture docs to keep updated: `OVERVIEW.md`, `BACKEND.md`, `FRONTEND.md` (create if missing).

## Environments (see BRANCHING.md)
- dev ← merge to `master` · qa ← push to `staging` branch · staging ← dispatch of the same sha · production ← tag `vX.Y.Z`.
- Hosting: <e.g. Hetzner CX33 running dev+qa+staging, separate production host>. URLs in `scripts/pipeline/pipeline.env`.
- Test data policy: <sandbox keys only, no production personal data outside production>.

## Engineering rules
- <layering, patterns to use / avoid, migration policy, logging rules, secrets>.
- Stop and ask before: destructive migrations, breaking API changes, auth or payment-flow changes.

## High-risk areas (QA and app specialist focus here)
- <e.g. payments/webhooks, state machines, uploads/permissions, authz, pagination caps>.

## Open strategic questions (do not assume resolved)
- <list>
