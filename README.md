# ship-pipeline — a Claude Code plugin

One `/ship <TICKET>` command runs the same delivery workflow in every project you work on:

```
Linear/Jira ticket ─► market-researcher ─► product-owner ─► business-analyst ─► senior-engineer
   ─► merge to master = DEV (build image :sha, engineer self-check)
   ─► push to staging branch = QA (qa-tester; defect tickets → engineer)
   ─► dispatch same sha = STAGING (app-specialist + marketing; defect tickets → engineer)
   ─► owner: go / no-go
   ─► tag vX.Y.Z = PRODUCTION (image re-tagged :vX.Y.Z; rollback on failure)
```

The seven personas are **generic**. Everything project-specific lives in two files in the project: `docs/pipeline/CONTEXT.md` (product, stack, test commands, rules, high-risk areas, brand, competitors) and `RELEASE_CHECKLIST.md`.

## Install the plugin (once per machine)

Push this folder to a git repo (e.g. `github.com/<you>/ship-pipeline`), then in Claude Code:

```
/plugin marketplace add <you>/ship-pipeline
/plugin install ship-pipeline@chris-plugins
```

(For a local checkout: `/plugin marketplace add /path/to/ship-pipeline`.) Update later with `/plugin update ship-pipeline`.

## Set up a project (once per repo, new or old)

```
cd ~/code/<project> && claude
/pipeline-init --name <project> --team-key <LINEAR-KEY>
```
Optional: `--profile reputabill` seeds CONTEXT.md and the checklist from a saved profile.

`/pipeline-init` scaffolds into the repo (and never overwrites your project-owned files on re-runs):

| Project-owned (created once, yours) | Tooling (refreshed each `/pipeline-init`) |
|---|---|
| `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md` | `scripts/pipeline/*.sh`, `scripts/pipeline/hooks/*` |
| `scripts/pipeline/pipeline.env` (URLs, branches, tracker) | `.claude/agents/*` (the personas) |
| `.github/workflows/deploy.yml`, `pipeline-gate.yml` | `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md`, `_templates/` |
| `scripts/deploy/{deploy,rollback,smoke}.sh`, `.claude/settings.json` | `tests/pipeline/*` |

The command then fills in CONTEXT.md from what it can read in the repo and asks you for the rest. Commit the result.

Then, per project:
1. Branches `master` (protected) and `staging`; make **Pipeline Gate** a required check on both.
2. GitHub environments `dev`, `qa`, `staging`, `production` with secret `DEPLOY_SSH_KEY` and vars `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, `APP_URL`.
3. Linear (or Jira) label groups `Stage` and `Owner` as listed in `docs/pipeline/TICKETS.md`; enable the tracker connector in Claude (cloud) or `claude mcp add --scope project` (local).
4. Hosts with a `docker-compose.yml` whose app service uses `image: ${IMAGE}` at `DEPLOY_PATH` (the engineer adapts `scripts/deploy/*` and `deploy.yml` on first use).

## Use

```
/ship REP-142            # start or resume a ticket
/pipeline-status REP-142 # where is it
```
Runs from the terminal, the Desktop app, or the iOS app as a cloud session (`docs/pipeline/CLOUD.md`). The run stops whenever a persona needs you (questions, a research "drop", go-live) — answer and run `/ship` again.

## Layout of this repo
```
.claude-plugin/               plugin.json + marketplace.json (repo is both plugin and marketplace)

commands/                    /ship, /pipeline-init, /pipeline-status
agents/                      the 7 generic personas (copied into projects, hooks intact)
scripts/pipeline/            gate, promote, next-version, intake, status, hooks
scripts/deploy/              Hetzner docker-compose deploy/rollback/smoke templates
template/                    files scaffolded into a project
profiles/<name>/             saved CONTEXT.md + RELEASE_CHECKLIST.md per product
tests/pipeline/              425 tests (bash); also installed into each project
```
`bash tests/pipeline/run-all.sh` runs everything, including an end-to-end install test.
