# ship-pipeline

A Claude Code plugin that runs one delivery process in every project: **`/ship <TICKET>`** takes a tracker ticket from requirement to a tagged production release. Personas do the work, tickets carry the handoffs, and scripts gate every promotion.

```
ticket ─► product owner ─► business analyst ─► senior engineer ─► devops: merge = DEV ─► qa-tester on QA
       ─► devops: same sha = STAGING ─► app specialist sign-off ─► owner: go ─► devops: tag vX.Y.Z = PRODUCTION
```

**Supported hosts:** GitHub, GitLab (including self-managed) and Bitbucket Cloud, each with its own CI.
**Trackers:** Jira, Linear, GitHub Issues and GitLab issues, or any tracker with an MCP connector as a fallback.
Everything runs through CLIs (`gh`, `glab`, `acli`, the Linear API), not MCP connectors.

## Install (once per machine)
```
/plugin marketplace add <you>/ship-pipeline
/plugin install ship-pipeline@chris-plugins
```
For a local checkout: `/plugin marketplace add /path/to/ship-pipeline`. To update: `/plugin update ship-pipeline`.

## Set up a project: `/pipeline-init`
Run it in the repository. It asks everything up front, in at most three rounds, with detected answers already selected:

| Question | Options |
|---|---|
| Git platform | GitHub, GitLab or Bitbucket, and a custom URL for a self-hosted host |
| Branching | trunk `main`/`master`, staging branch `staging`/`stable` |
| Ticketing platform | Jira, Linear, GitHub Issues or GitLab issues, its URL (Jira: the cloudId is looked up), and the ticket prefix (`ABC` for `ABC-12`) |
| Deployment strategy | deploy on branch merges, explicit deploys, or no environments; with environments, their URLs |
| Start level | Analysis, Engineering, DevOps or Quality Assurance (see [Teams and start levels](#teams-and-start-levels)) |
| Set up now | install CLIs; create and protect branches; create the tracker's labels, fields and statuses; turn deploys on |

Then it runs unattended:
1. Installs the tooling in one `scripts/init.sh` run. That takes seconds: only the adapters for your platforms, and no test suite.
2. Installs the missing CLIs.
3. Creates the branches and tracker workspace, and protects the branches.
4. Fills in `docs/pipeline/CONTEXT.md`, and ends with the readiness check.

**Your one manual step** is signing in, once, in a terminal: `bash scripts/pipeline/connect.sh login`. It runs the browser flows or asks for the tokens, and keeps tokens outside the repository.

Every answer is also an `init.sh` flag, so setup can be scripted: `--git-host`, `--git-url`, `--base-branch`, `--staging-branch`, `--tracker`, `--tracker-url`, `--team-key`, `--deploy-mode`, `--no-deploy-envs`, `--*-url`, `--start-at`, `--create-branches`. A re-run refreshes the tooling and never overwrites your project files.

## Use
```
/ship ABC-142            # start or resume a ticket; stops whenever it needs you (questions, go-live)
/pipeline-status ABC-142 # where it is, what it waits on
/pipeline-doctor         # is this repository ready? (seconds, read-only)
```
It runs from the terminal, the Desktop app, or the iOS app as a cloud session (`docs/pipeline/CLOUD.md`).

**Work without a ticket** (the install commit, a CI change, a dependency bump): open a PR/MR, and a human marks it infra so the Pipeline Gate skips the ticket requirement. On GitHub and GitLab that is the `infra` label; on Bitbucket it is a source branch named `infra/…`. Agents can never mark it infra themselves.

## How it works

### Teams and start levels
| Level | Personas | Mode | Produces |
|---|---|---|---|
| **Analysis** | `product-owner`, `business-analyst` | plan mode (read-only): they return a plan and `/ship` applies it | `product.md`, `requirements.md`, `story`/`eng` tickets |
| **Engineering** | `senior-engineer` | builds; never deploys | code, tests, `impl-notes.md`, then a handoff to devops |
| **DevOps** | `devops` | promotes; never edits application code | merge to dev, `dev-check.md`, the qa/staging/production promotions, rollback, CI/CD and infra |
| **Quality Assurance** | `qa-tester`, `app-specialist` | test and sign off | `qa-report.md`, `signoff.md`, `defect` tickets back to the engineer |

`PIPELINE_START_LEVEL` sets where a project picks tickets up. At `engineering`, tickets arrive analysed; at `devops`, built; at `qa`, already on qa. `scripts/pipeline/handover.sh` records the upstream teams' work at intake, so the gates stay just as strict. Every later stage always runs.

### Stages, gates and the release model
One sha travels three refs, and every environment runs the image built once on the way into dev.

| Stage | Who | Ref | Gate (`scripts/pipeline/gate.sh`) |
|---|---|---|---|
| build | engineer | ticket branch | product and requirements approved; `eng` tickets exist |
| dev | devops | merge → trunk | `eng` tickets done, no open defects, branch up to date |
| qa | devops | same sha → staging branch | dev check passed on that sha, no code change since |
| staging | devops | same sha dispatched | QA passed on that sha, its defects verified |
| production | devops, after the owner's go | tag `vX.Y.Z` | sign-off approved, every defect verified (no High wontfix), Go-live + Version recorded |

- `promote.sh` runs each gate, moves the ref, waits for the deploy, smoke-tests and records the release in `docs/pipeline/<TICKET>/releases.md`.
- `DEPLOY_MODE="explicit"` removes the push triggers, so `promote.sh` dispatches every environment itself.
- `PIPELINE_HAS_DEPLOY_ENVS="no"` skips the deploys; the refs still move.
- A code change after dev re-enters at dev. After three rework loops the ticket goes on hold.

### Tickets
The tracker is the source of truth; `docs/pipeline/<TICKET>/tickets.md` mirrors it for the gates and CI.
- The parent ticket carries two single-select groups, `Stage` and `Owner`. Children carry one kind: `story`, `eng`, `defect` or `follow-up`.
- Every handoff sets both groups and posts one comment.
- The personas use `scripts/pipeline/tracker.sh` for everything (`view`, `children`, `create`, `comment`, `handoff`, `state`, `setup`).

Protocol: `docs/pipeline/TICKETS.md`.

### Enforcement
- `hooks/guard-merge.sh` blocks an agent's push, merge or tag unless the ticket passes the gate for that ref. It covers `git`, `gh`, `glab` and `host.sh`. It also blocks force pushes and agents marking work infra.
- `hooks/allow-paths.sh` and `hooks/allow-commands.sh` confine each persona to the files and commands of its role.
- The CI Pipeline Gate re-checks pull requests. Branch protection makes it required where the plan allows; otherwise the pipeline says it runs in **local hook only** mode.

### Configuration: `scripts/pipeline/pipeline.env`
| Key | Meaning |
|---|---|
| `GIT_HOST`, `GIT_HOST_URL` | `github` / `gitlab` / `bitbucket`; the base URL of a self-hosted host |
| `BASE_BRANCH`, `STAGING_BRANCH`, `PIPELINE_REMOTE` | the trunk, the staging branch and the remote |
| `TRACKER`, `TRACKER_URL`, `TRACKER_CLOUD_ID`, `TRACKER_TEAM_KEY` | tracker, site, Jira cloudId, ticket prefix |
| `PIPELINE_START_LEVEL` | `analysis` / `engineering` / `devops` / `qa` |
| `DEPLOY_MODE`, `PIPELINE_HAS_DEPLOY_ENVS` | `merge` / `explicit`; `no` when there is nothing to deploy |
| `DEV_URL` … `PRODUCTION_URL`, `HEALTH_PATH` | the environments and their health check |

Project knowledge lives in `docs/pipeline/CONTEXT.md` and `RELEASE_CHECKLIST.md`. Put instructions for a persona under **Persona notes** in CONTEXT.md; the agent files are tooling and get refreshed.

## Repository layout
```
.claude-plugin/          plugin.json + marketplace.json
commands/                /ship, /pipeline-init, /pipeline-status, /pipeline-doctor
agents/                  the six personas (installed into .claude/agents/)
scripts/init.sh          the installer
scripts/pipeline/        gate, promote, intake, handover, status, next-version, doctor, connect, ci-gate, ci-resolve
  adapters/              host-<github|gitlab|bitbucket>.sh, tracker-<jira|linear|github|gitlab|connector>.sh:
                         init installs the chosen two as host.sh and tracker.sh
  lib/                   the code the adapters share
  hooks/                 guard-merge, allow-paths, allow-commands
  tracker-schema.txt     the labels, fields and statuses the tracker needs
scripts/deploy/          deploy / rollback / smoke templates (docker compose over SSH)
template/                files scaffolded into a project (docs, CI for each host, pipeline.env, checklist)
profiles/<name>/         saved CONTEXT.md + RELEASE_CHECKLIST.md per product
tests/pipeline/          the plugin's test suite (never installed into projects)
```

## Developing the plugin
`bash tests/pipeline/run-all.sh` runs every test file in parallel (`PIPELINE_TESTS_SERIAL=1` runs them one by one). Release notes and upgrade steps: [CHANGELOG.md](CHANGELOG.md).
