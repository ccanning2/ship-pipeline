# __PROJECT_NAME__ — Pipeline context (read by every persona)

The personas are generic; THIS file is what makes them behave correctly for this project. Keep it current — the product owner owns it.

## Product
- What it is, for whom, and how it's positioned (one paragraph).
- Brand: name, tagline, palette, tone. Claims that must NOT be made.
- User segments / roles: <e.g. customer, vendor, admin>.

## Constraints
- Regulatory notes: <data protection, payments, sector rules>.

## Stack & commands
- Backend: <framework, language, version>. Frontend: <framework>. Database: <db>.
- Backend tests: `<command>` (baseline: <n> tests — must never drop).
- Frontend tests: `<command>`. Lint/build: `<command>`.
- Docker: `<Dockerfile path>`; image: `ghcr.io/<owner>/<repo>:<sha>` (also tagged `:vX.Y.Z` in production).
- Architecture docs to keep updated: `OVERVIEW.md`, `BACKEND.md`, `FRONTEND.md` (create if missing).

## Environments (see BRANCHING.md)
- dev ← merge to `__BASE_BRANCH__` · qa ← push to `__STAGING_BRANCH__` branch · staging ← dispatch of the same sha · production ← tag `vX.Y.Z`.
- Hosting: <e.g. Hetzner CX33 running dev+qa+staging, separate production host>. URLs in `scripts/pipeline/pipeline.env`.
- Test data policy: <sandbox keys only, no production personal data outside production>.

## Project shape (set by /pipeline-init)
`scripts/pipeline/pipeline.env` is what the tooling reads; this section is what the personas read.
- Code host and tracker: <GitHub | GitLab | Bitbucket>, <Jira | Linear | GitHub Issues | GitLab issues>, ticket prefix <KEY>.
- Deploy strategy: <deploys on branch merges | explicit deploys>.
- Teams: <analysis, engineering, devops, qa, signoff: the ones selected>: who runs /ship here; tickets arrive at the first, and a later team left out is the owner's.
- `PIPELINE_HAS_DEPLOY_ENVS`: <yes | no>. <yes = hosts, an image and a deploy workflow exist. no = there
  is nothing to deploy to: `promote.sh` skips the deploy wait, the staging dispatch and smoke, and an
  "environment" is the ref people install from. The branch/tag promotion model is unchanged either way.>

## Engineering rules
- <layering, patterns to use / avoid, migration policy, logging rules, secrets>.
- Stop and ask before: destructive migrations, breaking API changes, auth or payment-flow changes.

## High-risk areas (QA and app specialist focus here)
- <e.g. payments/webhooks, state machines, uploads/permissions, authz, pagination caps>.

## Persona notes
Project-specific instructions for one persona go here, under its name, instead of into `.claude/agents/*.md`
(those are tooling: `/pipeline-init` refreshes them, and keeps a hand-edited copy only by skipping its update).
- <persona>: <instruction>

## Open strategic questions (do not assume resolved)
- <list>
