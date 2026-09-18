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
Optional: `--no-deploy-envs` and `--no-marketing` declare the project's shape (see **Project capabilities** below).

`/pipeline-init` scaffolds into the repo (and never overwrites your project-owned files on re-runs):

| Project-owned (created once, yours) | Tooling (refreshed each `/pipeline-init`) |
|---|---|
| `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md` | `scripts/pipeline/*.sh`, `scripts/pipeline/hooks/*` |
| `scripts/pipeline/pipeline.env` (URLs, branches, tracker) | `.claude/agents/*` (the personas) |
| `.github/workflows/deploy.yml` (unless `--no-deploy-envs`), `pipeline-gate.yml` | `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md`, `_templates/` |
| `scripts/deploy/{deploy,rollback,smoke}.sh` (unless `--no-deploy-envs`), `.claude/settings.json` | `tests/pipeline/*` |

The command then fills in CONTEXT.md from what it can read in the repo and asks you for the rest. Commit the result.

### Project capabilities

Not every project has hosts, and not every project has a marketing function. Two optional keys in `scripts/pipeline/pipeline.env` say so:

| Key | Default | `"no"` means |
|---|---|---|
| `PIPELINE_HAS_DEPLOY_ENVS` | `yes` | `/pipeline-init` creates no `scripts/deploy/*` and no `deploy.yml`; `promote.sh` performs no deploy wait, no staging workflow dispatch and no smoke call, and says so. The branch/tag promotion model, the gates, sign-off and go-live are unchanged. |
| `PIPELINE_HAS_MARKETING` | `yes` | The `marketing-specialist` persona is never invoked and the production gate never asks for launch content. `User-facing: yes\|no` goes back to meaning only "does this change affect users". |

A capability is off **only** when the value is exactly `no` (trimmed and lowercased). Absent, empty, `false`, `0` or a typo all resolve to `yes` — the stricter, original behaviour — so **an existing install that never adds these keys behaves exactly as it did before**. They are read from `pipeline.env` alone, never from the environment, so there is no per-ticket override. `bash scripts/pipeline/status.sh <TICKET>` prints the resolved values. `/pipeline-init` never deletes deploy files from an existing install: it reports them as kept and tells you to set the key by hand.

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

## Release notes

### v1.1.0
- New, optional `pipeline.env` keys **`PIPELINE_HAS_DEPLOY_ENVS`** and **`PIPELINE_HAS_MARKETING`** (`yes` | `no`). See **Project capabilities** above.
- Both default to `yes`. A capability is off only when the value is exactly `no`; absent, empty or misspelt values keep the stricter, original behaviour. **No existing install changes behaviour until its owner adds a key** — `pipeline.env` is project-owned and is never rewritten by `/pipeline-init`.
- `/pipeline-init` gains `--no-deploy-envs` and `--no-marketing`. On a *fresh* install they write the declared values and, for `--no-deploy-envs`, skip creating `scripts/deploy/*` and `.github/workflows/deploy.yml` and leave the deploy keys empty. On an *existing* install nothing is ever deleted: the files are reported as kept and you are told to set the key by hand.
- `promote.sh` skips the deploy wait, the staging workflow dispatch and the smoke call when there are no deployable environments, and says so. The branch/tag promotion model, the gates, sign-off and go-live are unchanged.
- The production gate asks for launch content only when the project has a marketing function **and** the ticket is `User-facing: yes`. This is the only pass/fail condition that changed.
- `gate.sh`'s PASS line and `status.sh` now report the resolved capabilities.

### v1.0.0
- First release: `/ship`, `/pipeline-init`, `/pipeline-status`, the seven personas, the branch/tag release model and the gate.
