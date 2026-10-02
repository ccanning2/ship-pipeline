# ship-pipeline

A Claude Code plugin that runs one delivery process in every project: **`/ship <TICKET>`** takes a tracker ticket from requirement to a tagged production release. Personas do the work, tickets carry the handoffs, and scripts gate every promotion.

```
ticket ─► product owner ─► business analyst ─► senior engineer ─► devops: merge = DEV ─► qa-tester on QA
       ─► devops: same sha = STAGING ─► app specialist sign-off ─► owner: go ─► devops: tag vX.Y.Z = PRODUCTION
```

**Supported hosts:** GitHub, GitLab (including self-managed) and Bitbucket Cloud, each with its own CI.
**Trackers:** Jira, Linear, GitHub Issues and GitLab issues, or any tracker with an MCP connector as a fallback.
Everything runs through CLIs (`gh`, `glab`, `acli`, the Linear API), not MCP connectors: see [CONNECTORS.md](CONNECTORS.md).

## Installation

Once per machine:

```bash
claude plugin marketplace add <you>/ship-pipeline
claude plugin install ship-pipeline@chris-plugins
```

Inside a session the same is `/plugin marketplace add <you>/ship-pipeline` and `/plugin install ship-pipeline@chris-plugins`. For a local checkout: `claude plugin marketplace add /path/to/ship-pipeline`. To update: `claude plugin update ship-pipeline`.

## Commands

Explicit workflows you invoke with a slash command. Each one is a skill in `skills/<name>/SKILL.md`.

| Command | Description |
|---|---|
| `/ship` | Run one tracker ticket through the pipeline, from requirement to a production tag, with the project's teams. Resumable |
| `/pipeline-init` | Install or update the pipeline in a repository: one interview up front, then CLIs, branches, tracker workspace and CI set up unattended |
| `/pipeline-status` | Where a ticket is, what it waits on, and which sha is in each environment |
| `/pipeline-doctor` | Is this repository ready for `/ship`? Read-only, takes seconds |

`/ship` and `/pipeline-init` push, merge, tag and change the tracker, so they run only when you type them (`disable-model-invocation`). `/pipeline-status` and `/pipeline-doctor` are read-only, and Claude also uses them on its own when you ask where a ticket is or whether a repository is ready.

## Agents

The personas `/ship` hands each stage to. `/pipeline-init` installs them into the project's `.claude/agents/`.

| Agent | Team | Does |
|---|---|---|
| `product-owner` | Analysis | Turns the requirement into a product definition (`product.md`). Plan mode, read-only |
| `business-analyst` | Analysis | Turns the product definition into requirements and `eng` tickets (`requirements.md`). Plan mode, read-only |
| `senior-engineer` | Engineering | Builds the change and its tests; hands the build to devops. Never deploys |
| `devops` | DevOps | Merges to dev, checks it, promotes the same sha to qa, staging and a production tag; rolls back. Never edits application code |
| `qa-tester` | QA | Tests on qa against `requirements.md`; raises `defect` tickets. Edits test code only |
| `app-specialist` | Sign-off | Checks staging against `RELEASE_CHECKLIST.md`; approves for go-live or raises `defect` tickets. Never edits code |

## Example workflows

### Set up a project

```
/pipeline-init
```

Run it in the repository. It asks everything before installing, in at most three rounds (paused once for the sign-in), with detected answers already selected:

| Question | Options |
|---|---|
| Git platform | GitHub, GitLab or Bitbucket, and a custom URL for a self-hosted host |
| Branching | trunk `main`/`master`, staging branch `staging`/`stable` |
| Ticketing platform | Jira (with its site; the cloudId is looked up), Linear, GitHub Issues or GitLab issues |
| Team or project | for Linear and Jira, asked after the sign-in: the teams or projects your account can see, the detected one recommended. For GitHub or GitLab Issues, the ticket prefix (`ABC` for `ABC-12`) |
| Deployment strategy | deploy on branch merges, explicit deploys, or no environments; with environments, their URLs |
| Teams | any of Analysis, Engineering, DevOps, QA and Sign-off (see [Teams](#teams)) |
| Set up now | install CLIs; create and protect branches; create the tracker's labels, fields and statuses; turn deploys on |

Then it runs unattended:
1. Installs the tooling in one `scripts/init.sh` run. That takes seconds: only the adapters for your platforms, and no test suite.
2. Installs the missing CLIs.
3. Creates the branches and tracker workspace, and protects the branches.
4. Fills in `docs/pipeline/CONTEXT.md`, and ends with the readiness check.

**Your one manual step** is signing in, once, in a terminal, right after the first round of questions: `/pipeline-init` gives you the exact `connect.sh ... login` command (later, `bash scripts/pipeline/connect.sh login`). It runs the browser flows or asks for the tokens, and keeps tokens outside the repository. For Linear and Jira the sign-in comes first so the next round can list your real teams or projects (`connect.sh teams`) instead of asking you for the key.

Every answer is also an `init.sh` flag, so setup can be scripted: `--git-host`, `--git-url`, `--base-branch`, `--staging-branch`, `--tracker`, `--tracker-url`, `--team-key`, `--deploy-mode`, `--no-deploy-envs`, `--*-url`, `--teams`, `--create-branches`. A re-run refreshes the tooling and never overwrites your project files.

### Ship a ticket

```
/ship ABC-142                 # start or resume a ticket; stops whenever it needs you (questions, go-live)
/ship ABC-142 with analysis   # this ticket only: other teams than the project's, in your own words
/pipeline-status ABC-142      # where it is, what it waits on
/pipeline-doctor              # is this repository ready? (seconds, read-only)
```
It runs from the terminal, the Desktop app, or the iOS app as a cloud session (`docs/pipeline/CLOUD.md`).

**One ticket, other teams.** Say what you want after the ticket id: "with analysis" when a ticket needs the product owner and business analyst in a project that has them off, "no QA", "engineer and qa-tester only", or "it's already on qa". There are no flags to remember. `/ship` works out the teams, asks you once to confirm, and records them in the ticket's `STATUS.md` (`teams.sh <TICKET> --set`), so a resume keeps them. On a ticket already under way, the change applies from the current stage on. Another repository or tracker is the project's setup, not a ticket's, so `/ship` sends you to `/pipeline-init` for it.

**While it runs you see a board, not the personas' reasoning.** After each stage `/ship` shows only this:

```
ABC-142  Add a health endpoint             teams: analysis,engineering,devops,qa,signoff
────────────────────────────────────────────────────────────────────────────────
 ✓ product     product-owner
 ✓ analysis    business-analyst/product-owner
 ▶ build       senior-engineer                 ABC-143: health route + test
 · dev         devops
 · qa          qa-tester
 · staging     app-specialist
 · go-live     the owner
 · production  devops
────────────────────────────────────────────────────────────────────────────────
 progress [######..............]  31%  2 of 8 stages done or skipped, 1 under way
 dev -  qa -  staging -  prod -    open defects: 0
 last handoffs
   14:02  business-analyst → senior-engineer: 2 eng tickets ready
```

To watch it live:
- Run `/ship` inside **tmux** and the board opens in a side pane that redraws itself.
- Anywhere else, run `bash scripts/pipeline/board.sh ABC-142 --watch` in a second terminal.
- `board.sh --all` lists every ticket in flight with its progress. The percentage is an estimate: a stage done or skipped counts in full, the one under way as half. `status.sh <TICKET>` adds the share of gates cleared.

The detail stays in `docs/pipeline/ABC-142/` and on the tracker ticket.

**Work without a ticket** (the install commit, a CI change, a dependency bump): open a PR/MR, and a human marks it infra so the Pipeline Gate skips the ticket requirement. On GitHub and GitLab that is the `infra` label; on Bitbucket it is a source branch named `infra/…`. Agents can never mark it infra themselves. The one exception is the pipeline's own install or upgrade: with "Branches" ticked, `/pipeline-init` merges its install request itself, without a human review, through `scripts/pipeline/install-merge.sh`, which accepts nothing but the plugin's own files. If the host or the guard refuses (a required review or check, a missing permission), the request stays open, and you mark it infra and merge it. Want a human review of the install? Leave "Branches" unticked, or keep a required review on the trunk.

## Integrations

> If you see unfamiliar `~~category` placeholders or need to check which tools are used, see [CONNECTORS.md](CONNECTORS.md).

| Category | Supported | What it enables |
|---|---|---|
| **Code host** | GitHub, GitLab, Bitbucket Cloud | branches, pull requests, merges, tags, branch protection |
| **Project tracker** | Jira, Linear, GitHub Issues, GitLab issues; any tracker's MCP connector as a fallback | the handoffs: Stage/Owner labels, child tickets, comments, statuses |
| **CI/CD** | GitHub Actions, GitLab CI, Bitbucket Pipelines | the required Pipeline Gate check, the deploys |
| **Deploy target** | docker compose over SSH, or your own script | dev, qa, staging and production environments and their smoke tests |

The plugin ships no `.mcp.json`: every category is reached through a CLI, signed in once by `/pipeline-init`.

## How it works

### Teams
| Team | Personas | Mode | Produces |
|---|---|---|---|
| **Analysis** | `product-owner`, `business-analyst` (always together) | plan mode (read-only): they return a plan and `/ship` applies it | `product.md`, `requirements.md`, `story`/`eng` tickets |
| **Engineering** | `senior-engineer` | builds; never deploys | code, tests, `impl-notes.md`, then a handoff to devops |
| **DevOps** | `devops` | promotes; never edits application code | merge to dev, `dev-check.md`, the qa/staging/production promotions, rollback, CI/CD and infra |
| **QA** | `qa-tester` | tests on qa; needs DevOps | `qa-report.md`, `defect` tickets back to the engineer |
| **Sign-off** | `app-specialist` | checks staging against the release checklist; needs DevOps | `signoff.md`, `defect` tickets back to the engineer |

`PIPELINE_TEAMS` selects the teams, for example `"engineering,devops,qa"` for an engineer, a QA tester and DevOps overseeing the promotions. Tickets arrive at the first selected team: at `engineering` analysed, at `devops` built. `scripts/pipeline/handover.sh` records the upstream work at intake, so the gates stay just as strict. A later team you leave out is yours: with DevOps selected, `/ship` hands you that stage (the build, the QA pass or the sign-off), waits, and records it; without DevOps, the run ends after the last selected team. `bash scripts/pipeline/teams.sh <TICKET> --stages` shows who runs each stage.

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
- `hooks/guard-merge.sh` blocks an agent's push, merge or tag unless the ticket passes the gate for that ref. It covers `git`, `gh`, `glab` and `host.sh`. It also blocks force pushes and agents marking work infra. It lets one ticketless route through: `install-merge.sh`, run alone, when the plugin's own `init.sh` confirms the commit is nothing but the install.
- `hooks/allow-paths.sh` and `hooks/allow-commands.sh` confine each persona to the files and commands of its role.
- The CI Pipeline Gate re-checks pull requests. Branch protection makes it required where the plan allows; otherwise the pipeline says it runs in **local hook only** mode.

## Settings

`/pipeline-init` writes the project's settings to `scripts/pipeline/pipeline.env` from your answers, and asks for them interactively when they are missing. A re-run never overwrites it; it proposes each change as a diff.

| Key | Meaning |
|---|---|
| `GIT_HOST`, `GIT_HOST_URL` | `github` / `gitlab` / `bitbucket`; the base URL of a self-hosted host |
| `BASE_BRANCH`, `STAGING_BRANCH`, `PIPELINE_REMOTE` | the trunk, the staging branch and the remote |
| `TRACKER`, `TRACKER_URL`, `TRACKER_CLOUD_ID`, `TRACKER_TEAM_KEY` | tracker, site, Jira cloudId, ticket prefix |
| `PIPELINE_TEAMS` | the teams that run `/ship`: `analysis`, `engineering`, `devops`, `qa`, `signoff` (installs before 3.1.0 have `PIPELINE_START_LEVEL` instead, read as that level and every team after it) |
| `DEPLOY_MODE`, `PIPELINE_HAS_DEPLOY_ENVS` | `merge` / `explicit`; `no` when there is nothing to deploy |
| `DEV_URL` … `PRODUCTION_URL`, `HEALTH_PATH`, `SMOKE_EXPECT` | the environments and their smoke test: `<URL><HEALTH_PATH>` must answer 2xx and, when set, contain `SMOKE_EXPECT` |

Project knowledge lives in `docs/pipeline/CONTEXT.md` and `RELEASE_CHECKLIST.md`. Put instructions for a persona under **Persona notes** in CONTEXT.md; the agent files are tooling and get refreshed.

## Repository layout
```
.claude-plugin/          plugin.json + marketplace.json
skills/<name>/SKILL.md   /ship, /pipeline-init, /pipeline-status, /pipeline-doctor
agents/                  the six personas (installed into .claude/agents/)
CONNECTORS.md            the ~~category placeholders and the CLI behind each
scripts/init.sh          the installer
scripts/pipeline/        gate, promote, intake, handover, board, status, next-version, doctor, connect, ci-gate, ci-resolve,
                         install-merge (init's merge of its own install)
  adapters/              host-<github|gitlab|bitbucket>.sh, tracker-<jira|linear|github|gitlab|connector>.sh:
                         init installs the chosen two as host.sh and tracker.sh
  lib/                   the code the adapters share
  hooks/                 guard-merge, allow-paths, allow-commands
  tracker-schema.txt     the labels, fields and statuses the tracker needs
scripts/deploy/          deploy / rollback / smoke templates (docker compose over SSH; the host key is verified against DEPLOY_KNOWN_HOSTS)
template/                files scaffolded into a project (docs, CI for each host, pipeline.env, checklist)
profiles/<name>/         saved CONTEXT.md + RELEASE_CHECKLIST.md per product
tests/pipeline/          the plugin's test suite (never installed into projects)
```

## Developing the plugin
`bash tests/pipeline/run-all.sh` runs every test file in parallel and streams each file's result in order as it finishes, with a `[n/N]` progress line and a pass/fail total (`PIPELINE_TESTS_SERIAL=1` runs them one by one). Release notes and upgrade steps: [CHANGELOG.md](CHANGELOG.md).
