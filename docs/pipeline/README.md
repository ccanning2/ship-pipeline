# Delivery pipeline (installed by the ship-pipeline plugin)

Run `/ship <TICKET>` on a tracker ticket that holds the requirement. It runs with this project's teams (`PIPELINE_TEAMS`: analysis, engineering, devops, qa, signoff; `scripts/pipeline/teams.sh` resolves them). Personas hand off through the ticket (`TICKETS.md`); code promotes through branches and tags (`BRANCHING.md`); all project knowledge lives in `CONTEXT.md` and `RELEASE_CHECKLIST.md`.

| Persona | Model | Writes | Responsibility |
|---|---|---|---|
| product-owner | opus, plan mode | product.md, tickets (as a plan /ship applies) | Fleshes out the requirement; answers the BA |
| business-analyst | opus, plan mode | requirements.md, eng tickets (as a plan /ship applies) | Engineer-ready spec |
| senior-engineer | opus | code, tests | Builds the eng/defect tickets, hands the build to devops |
| devops | opus | CI/CD, deploy scripts, infra, dev-check.md | Promotes dev → qa → staging → production, rolls back |
| qa-tester | sonnet | tests, qa-report.md, defect tickets | Tests on QA |
| app-specialist | opus | signoff.md, defect tickets | Staging sign-off against RELEASE_CHECKLIST |

Write boundaries are enforced by hooks (`scripts/pipeline/hooks/allow-paths.sh`, and `allow-commands.sh` for the personas whose only shell command is the tracker CLI); merges/pushes/tags are gated by `scripts/pipeline/hooks/guard-merge.sh` and by CI.
Tickets go through `scripts/pipeline/tracker.sh` (Jira, Linear, GitHub Issues or GitLab issues via their CLIs); the code host through `scripts/pipeline/host.sh` (GitHub, GitLab or Bitbucket). Sign in once with `bash scripts/pipeline/connect.sh login`.

Commands: `/ship <TICKET>`, `/pipeline-status <TICKET>`, `/pipeline-doctor` (is this repo ready?), `/pipeline-init` (update tooling).
Project-specific instructions for a persona: **Persona notes** in `CONTEXT.md` (the agent files are tooling and are refreshed).
Scripts: `scripts/pipeline/{status,gate,promote,next-version,doctor,tracker,host,connect}.sh`, `scripts/deploy/rollback.sh`.
The tooling's own test suite lives in the ship-pipeline plugin, not in this project.
Cloud sessions (run from the phone): `CLOUD.md`.
