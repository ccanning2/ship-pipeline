# Delivery pipeline (installed by the ship-pipeline plugin)

Run `/ship <TICKET>` on a tracker ticket that holds the requirement. Personas hand off through the ticket (`TICKETS.md`); code promotes through branches and tags (`BRANCHING.md`); all project knowledge lives in `CONTEXT.md` and `RELEASE_CHECKLIST.md`.

| Persona | Model | Writes | Responsibility |
|---|---|---|---|
| market-researcher | opus | research.md | First: product fit, competitors, customer value |
| product-owner | opus | product.md, tickets | Fleshes out the requirement; answers the BA |
| business-analyst | opus | requirements.md, eng tickets | Engineer-ready spec |
| senior-engineer | opus | code, tests, CI/CD, infra | Build → dev self-check → qa → staging → production |
| qa-tester | sonnet | tests, qa-report.md, defect tickets | Tests on QA |
| app-specialist | opus | signoff.md, defect tickets | Staging sign-off against RELEASE_CHECKLIST |
| marketing-specialist | sonnet | marketing.md, launch ticket | Look & feel, then launch content |

Write boundaries are enforced by hooks (`scripts/pipeline/hooks/allow-paths.sh`); merges/pushes/tags are gated by `scripts/pipeline/hooks/guard-merge.sh` and by CI.

Commands: `/ship <TICKET>`, `/pipeline-status <TICKET>`, `/pipeline-init` (update tooling).
Scripts: `scripts/pipeline/{status,gate,promote,next-version}.sh`, `scripts/deploy/rollback.sh`.
Tests: `bash tests/pipeline/run-all.sh`.
Cloud sessions (run from the phone): `CLOUD.md`.
