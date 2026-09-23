# ship-pipeline — a Claude Code plugin

One `/ship <TICKET>` command runs the same delivery workflow in every project you work on:

```
Jira/Linear/GitHub/GitLab ticket ─► market-researcher ─► product-owner ─► business-analyst ─► senior-engineer
   ─► merge to the base branch (main, master, …) = DEV (build image :sha, engineer self-check)
   ─► push to staging branch = QA (qa-tester; defect tickets → engineer)
   ─► dispatch same sha = STAGING (app-specialist + marketing; defect tickets → engineer)
   ─► owner: go / no-go
   ─► tag vX.Y.Z = PRODUCTION (image re-tagged :vX.Y.Z; rollback on failure)
```

**Supported hosts:** GitHub + GitHub Actions (`gh`, GitHub Enterprise too), GitLab + GitLab CI (`glab`, self-managed too) and Bitbucket Cloud + Bitbucket Pipelines (REST with an API token). **Trackers:** Jira (`acli` + REST), Linear (GraphQL API), GitHub Issues (`gh`) and GitLab issues (`glab`), or any tracker with an MCP connector as a fallback. Everything goes through CLIs: `scripts/pipeline/host.sh` for the code host, `scripts/pipeline/tracker.sh` for tickets.

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
/pipeline-init
```
`/pipeline-init` asks every question up front, with the answers it could detect already selected. It asks at most three rounds of multiple choice:
- **Git platform:** GitHub, GitLab or Bitbucket, and a custom URL for a self-hosted one.
- **Branching strategy:** the trunk (`main`/`master`) and the staging branch (`staging`/`stable`).
- **Ticketing platform:** Jira, Linear, GitHub Issues or GitLab issues, plus its URL (the Jira site, from which it resolves the cloudId) and the ticket prefix (`ABC` for `ABC-12`).
- **Marketing function:** yes or no.
- **Deployment strategy:** deploys on branch merges, explicit deploys, or no environments. With environments, it also asks for their URLs.
- **One consent question** covering what it may set up: install the CLIs; create and protect the branches; create the tracker's labels, custom fields and statuses; turn deploys on.

Then it installs everything in one run of `scripts/init.sh` (seconds, no test suite), then:
1. Installs the missing CLIs with `connect.sh install` (winget, brew, apt or dnf).
2. Asks you for the one thing only you can do: run `bash scripts/pipeline/connect.sh login` once in a terminal. That signs in to every tool through its browser flow or a token you type, and keeps tokens outside the repo.
3. Creates the tracker workspace with `tracker.sh setup`, and protects the branches.
4. Fills in CONTEXT.md, and ends with the readiness check.

Every answer is also a flag (`--git-host`, `--git-url`, `--base-branch`, `--staging-branch`, `--tracker`, `--tracker-url`, `--team-key`, `--no-marketing`, `--no-deploy-envs`, `--deploy-mode merge|explicit`, `--dev-url` …, `--create-branches`), so `scripts/init.sh` also runs unattended. Optional: `--profile reputabill` seeds CONTEXT.md and the checklist from a saved profile.

`/pipeline-init` scaffolds into the repo (and never overwrites your project-owned files on re-runs):

| Project-owned (created once, yours) | Tooling (refreshed each `/pipeline-init`) |
|---|---|
| `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md` | `scripts/pipeline/*.sh`, `scripts/pipeline/hooks/*` |
| `scripts/pipeline/pipeline.env` (host, branches, tracker, URLs), `scripts/pipeline/tracker.map` | `.claude/agents/*` (the personas) |
| The CI files for your host: `.github/workflows/{deploy,pipeline-gate}.yml`, or `.gitlab/pipeline-{gate,deploy}.yml` included from `.gitlab-ci.yml`, or `bitbucket-pipelines.yml` (no deploy files with `--no-deploy-envs`) | `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md`, `_templates/` |
| `scripts/deploy/{deploy,rollback,smoke}.sh` (unless `--no-deploy-envs`), `.claude/settings.json` | |

The plugin's own test suite is **not** installed into projects (it tests the tooling, and an older install's untouched copy is removed on the next run). Commit the result.

**Hand-edited tooling is kept.** `scripts/pipeline/.install-manifest` records every tooling file as installed. On a re-run, a file edited since then is left alone and the new version is written beside it as `<file>.new`; `--force-tooling` takes the new versions. Put project-specific instructions for a persona under **Persona notes** in `docs/pipeline/CONTEXT.md` rather than in `.claude/agents/*.md`, and nothing needs editing.

**`.gitignore`** gains `.claude/.pipeline-ticket` and `.claude/settings.local.json` once, under a `# ship-pipeline` comment.

### Is it ready? `/pipeline-doctor`

A read-only check (`scripts/pipeline/doctor.sh`, seconds) that reports PASS / WARN / FAIL for:
- installed files and permissions;
- `pipeline.env`: host, branches, remote, team key, a ticket regex that doesn't also match `macos-14` or `v1.45.0-jammy`, placeholder URLs and capabilities;
- the remote: it exists, is the configured host, has the base and staging branches, and **shares history with your local repo**;
- the host CLI sign-in and the enforcement mode;
- the guard hook wiring, the CI files and leftover `master` literals;
- the tracker workspace, through its CLI (`tracker.sh check` and `setup --check`): the team, both single-select label groups, the kind labels and the workflow statuses (`scripts/pipeline/tracker-schema.txt`).

It offers to create what is missing, and creates only what you approve. `/pipeline-init` runs it at the end.

### Project capabilities

Not every project has hosts, and not every project has a marketing function. Two optional keys in `scripts/pipeline/pipeline.env` say so:

| Key | Default | `"no"` means |
|---|---|---|
| `PIPELINE_HAS_DEPLOY_ENVS` | `yes` | `/pipeline-init` creates no `scripts/deploy/*` and no `deploy.yml`; `promote.sh` performs no deploy wait, no staging workflow dispatch and no smoke call, and says so. The branch/tag promotion model, the gates, sign-off and go-live are unchanged. |
| `PIPELINE_HAS_MARKETING` | `yes` | The `marketing-specialist` persona is never invoked and the production gate never asks for launch content. `User-facing: yes\|no` goes back to meaning only "does this change affect users". |

A capability is off **only** when the value is exactly `no` (trimmed and lowercased). Absent, empty, `false`, `0` or a typo all resolve to `yes` — the stricter, original behaviour — so **an existing install that never adds these keys behaves exactly as it did before**. They are read from `pipeline.env` alone, never from the environment, so there is no per-ticket override. `bash scripts/pipeline/status.sh <TICKET>` prints the resolved values. `/pipeline-init` never deletes deploy files from an existing install: it reports them as kept and tells you to set the key by hand. Re-running it over a project whose `pipeline.env` already says `PIPELINE_HAS_DEPLOY_ENVS="no"` refreshes the tooling without recreating `scripts/deploy/*` or `deploy.yml` — the declared shape is read from the file, so the flag does not have to be repeated.

`/pipeline-init` sets up the branches, branch protection, the tracker workspace and the CLIs itself. What stays with you:
1. **Enforcement where the plan refuses it.** A private repository on GitHub's free plan cannot have branch protection or rulesets (HTTP 403), and Bitbucket's "require passing builds" is a Premium feature. The pipeline then runs in **local hook only** mode, where the hook gates agent sessions but a human or another tool can push past it. `/pipeline-status` and `/pipeline-doctor` say which mode you are in.
2. **Deploy targets and secrets:**
   - Environments `dev`, `qa`, `staging` and `production`, each with the SSH key and `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, `APP_URL`. The CI file header for your host says exactly where these go.
   - Hosts with a `docker-compose.yml` whose app service uses `image: ${IMAGE}` at `DEPLOY_PATH`. The engineer adapts `scripts/deploy/*` and the CI file on first use.
   - Deploys stay off until `PIPELINE_DEPLOY_ENABLED` is `true`, so CI is not red before the hosts exist. `/pipeline-init` sets it when you tick "Deploys on".
3. **A Jira workflow edit, if needed.** A status that `tracker.sh setup` creates must be added to the project's workflow; until then the pipeline state is mapped to the nearest existing status (`scripts/pipeline/tracker.map`).

## Use

```
/ship REP-142            # start or resume a ticket
/pipeline-status REP-142 # where is it
```
Runs from the terminal, the Desktop app, or the iOS app as a cloud session (`docs/pipeline/CLOUD.md`). The run stops whenever a persona needs you (questions, a research "drop", go-live) — answer and run `/ship` again.

**Work without a ticket** (the install commit, a CI migration, a dependency bump): push a branch and open a PR/MR. A human reviews it and marks it infra, and the Pipeline Gate then skips the ticket requirement: the **`infra`** label on GitHub or GitLab, or on Bitbucket (which has no PR labels) a source branch named `infra/…`. The same human merges it. Agents cannot add that label or force-push, and there is no override an agent can set for itself. The hook gates agent tool calls only, so you can always run such a command in your own terminal.

## Layout of this repo
```
.claude-plugin/               plugin.json + marketplace.json (repo is both plugin and marketplace)

commands/                    /ship, /pipeline-init, /pipeline-status, /pipeline-doctor
agents/                      the 7 generic personas (copied into projects, hooks intact)
scripts/pipeline/            gate, promote, next-version, intake, status, doctor, hooks; ticket-id, base-ref and
                             enforcement (the one definition of a ticket id, the trunk and the enforcement mode);
                             host.sh / tracker.sh (the code host and the tracker, through their CLIs), connect.sh
                             (install + sign in), ci-gate.sh / ci-resolve.sh (shared by the GitLab/Bitbucket CI);
                             tracker-schema.txt (the labels, fields and statuses the tracker needs)
scripts/deploy/              Hetzner docker-compose deploy/rollback/smoke templates
template/                    files scaffolded into a project
profiles/<name>/             saved CONTEXT.md + RELEASE_CHECKLIST.md per product
tests/pipeline/              the tooling's test suite (bash); stays in the plugin, never installed into projects
```
`bash tests/pipeline/run-all.sh` runs everything, including an end-to-end install test.

## Release notes

### v2.0.1

Fixes found by running `/pipeline-init` on a fresh test repository:
- **winget installs work on Windows.** winget puts portable packages such as jq and glab under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, and not always on `PATH`, so `connect.sh install` reported them installed although they could not be run. It now copies the exe into `~/bin` and reports `INSTALLED` only once the tool is found. A re-run no longer fails because winget says the package is already installed.
- **One clear tracker error.** A missing Linear key or Jira token or site is now reported once, before any API call, instead of being followed by a misleading "no team with key …".
- **Placeholder URLs.** The doctor flags only the `.example.invalid` placeholders that init writes, not real URLs that contain "example".
- **Staging branch advice.** The doctor's missing-staging-branch advice now points at `/pipeline-init`'s Branches option.

### v2.0.0

`/pipeline-init` is now a single upfront interview followed by an unattended setup. Everything goes through CLIs, not MCP connectors.
- **All questions up front.** It asks the Git platform (GitHub, GitLab or Bitbucket, with a custom URL), the branching strategy (`main`/`master`, `staging`/`stable`), the ticketing platform (URL/cloudId and ticket prefix), the marketing function and the deployment strategy (environment URLs; deploy on merge or explicitly). One consent answer then covers every setup action. Every answer has an `init.sh` flag.
- **Fast.**
  - The plugin's test suite is no longer run by `/pipeline-init` or copied into projects. An old untouched copy is removed.
  - `init.sh` plans all copies and compares checksums in batches: a fresh install went from about 19s to about 6s on Windows.
  - The doctor takes seconds and has no test step unless you ask for it.
- **CLIs for everything:**
  - `scripts/pipeline/connect.sh` finds, installs and signs in to the CLIs. The one owner step is `connect.sh login` in a terminal.
  - `scripts/pipeline/tracker.sh` reads and changes tickets, and sets up labels, custom fields and statuses, for Jira (`acli` + REST), Linear (GraphQL), GitHub Issues (`gh`) and GitLab issues (`glab`). `TRACKER=connector` keeps an MCP connector as the fallback.
  - `scripts/pipeline/host.sh` does merges, ref updates, deploy dispatch and wait, CI variables, branch protection and the enforcement check for GitHub, GitLab and Bitbucket.
- **Every host has CI.** New templates: `.gitlab/pipeline-gate.yml` and `.gitlab/pipeline-deploy.yml` (included from `.gitlab-ci.yml`), and `bitbucket-pipelines.yml`. They share `ci-gate.sh` and `ci-resolve.sh` with the gate logic.
- **Deploy mode.** `DEPLOY_MODE="explicit"` drops the push and tag triggers, and `promote.sh` dispatches every environment after its gate. `merge` (the default) is the v1 behaviour.
- **Personas.** Every persona uses `tracker.sh`. The four that had no shell (research, product, analysis, marketing) may now run that one script and nothing else, enforced by `hooks/allow-commands.sh`. The guard hook also gates `glab` merges and tags, `host.sh merge|set-ref`, and agent pushes of `infra/` branches on Bitbucket.

#### Upgrading from v1.1.0
Run `/pipeline-init`. Tooling refreshes as before, and `pipeline.env` is still never rewritten. A v1.1.0 `pipeline.env` without the new keys behaves exactly as before: `GIT_HOST` defaults to `github`, `TRACKER` to `linear` and `DEPLOY_MODE` to `merge`. Add `GIT_HOST`, `GIT_HOST_URL`, `TRACKER_URL`, `TRACKER_CLOUD_ID` and `DEPLOY_MODE` when you want to change them; `/pipeline-init` proposes the lines. Then:
- Run `bash scripts/pipeline/connect.sh login` once.
- Run `bash scripts/pipeline/tracker.sh setup --check` to see whether the tracker workspace already matches.
- Delete the `self-test` step from your installed `pipeline-gate.yml`: there is no longer a suite in the project to run.

### v1.1.0

Changes from installing the pipeline into a repository whose trunk is `main`, that was moving from GitLab to GitHub, had no deployed environments and tracked work in Linear.

- **`/pipeline-doctor`** (`scripts/pipeline/doctor.sh`): a read-only readiness check, also run at the end of `/pipeline-init`. See **Is it ready?** above.
- **No more hardcoded `master`.** `/pipeline-init` detects the trunk (`--base-branch`, `--staging-branch`) and fills `__BASE_BRANCH__` / `__STAGING_BRANCH__` in workflows, docs and templates. Agents and scripts ask `scripts/pipeline/base-ref.sh` instead of naming a branch.
- **Narrow ticket ids, defined once.** New installs match `<TEAM KEY>-<number>` only. `scripts/pipeline/ticket-id.sh` is the one definition that the hook, the gate and both workflows read; the PR gate no longer carries its own copy of the regex, and an id must stand alone (`xREP-1` is not `REP-1`). Existing `pipeline.env` files keep their regex, and the doctor warns when it is broad.
- **Guard hook:** it now parses each simple command, so `echo`, `grep`, pipes, commit messages and heredoc bodies never trip it, and it also gates branch and tag moves made through `gh api`. It refuses an agent's force push or delete of the base branch, the staging branch or a version tag, bulk pushes, and adding the `infra` label. A block now explains the ways forward: `/ship`, an `infra` PR, or the owner's own terminal.
- **`infra` PRs:** the Pipeline Gate skips the ticket requirement for a PR a human labels `infra`, and runs the tooling self-test only when pipeline tooling changed.
- **`deploy.yml` ships switched off** until the repository variable `PIPELINE_DEPLOY_ENABLED` is `true`.
- **`PIPELINE_REMOTE`** (default `origin`) names the code host's remote; `promote.sh` and the gate no longer assume `origin`.
- **Enforcement mode:** `scripts/pipeline/enforcement.sh` reports whether the host requires the Pipeline Gate check or only the local hook enforces it (for example on a private free-plan repository); `/pipeline-status` and `BRANCHING.md` say so.
- **Tracker setup as data:** `scripts/pipeline/tracker-schema.txt` lists the label groups, kind labels and statuses; `TICKETS.md` explains single-select groups and the missing **In Review** status.
- **Installer hygiene:** no `.gitignore.pipeline` file is left in the project, and the entries are added once under `# ship-pipeline` (older leftovers are cleaned up). Hand-edited tooling files are kept, with the new version written as `<file>.new`; the new **Persona notes** section in `CONTEXT.md` removes the need to edit agents.
- **Upgrading:** see **Upgrading from v1.0.0** below. Nothing changes in an existing install until you approve it.

#### Upgrading from v1.0.0

Run `/plugin update ship-pipeline`, then `/pipeline-init` in each project. It refreshes the tooling (scripts, hooks, agents, generic docs) and cleans the old `.gitignore` leftovers. Your `pipeline.env` and `.github/workflows/*` are project-owned, so they are never rewritten, and until you change them the project behaves as it did under v1.0.0. `/pipeline-doctor` marks each thing still to change with `[upgrade: …]`. `/pipeline-init` then shows each change as a diff against the new template and applies only what you approve:

| Doctor finding | Change | Notes |
|---|---|---|
| `PIPELINE_REMOTE is not set` | add `PIPELINE_REMOTE="origin"` to `pipeline.env` | Harmless to skip: `origin` is the default. Name another remote here if GitHub isn't `origin`. |
| `PIPELINE_TICKET_REGEX … also matches macos-14 …` | replace the regex line with `PIPELINE_TICKET_REGEX="${TRACKER_TEAM_KEY:-}-[0-9]+"` | Check first that every ticket in `docs/pipeline/*/` and on open branches uses your team key. Ids with another prefix would stop matching. |
| `pipeline-gate.yml predates v1.1.0` | take the new template's *Verify gate* and *self-test* steps and its `types:` line | Adds the `infra` label route, the shared ticket id and the path-filtered self-test. Keep any steps of your own. |
| `deploy.yml runs on every push …` | add `if: vars.PIPELINE_DEPLOY_ENABLED == 'true'` to the `resolve` job, then set that repository variable to `true` once your environments work | Or delete `deploy.yml` if `PIPELINE_HAS_DEPLOY_ENVS="no"`. |
| `'master' still appears in: .github/workflows/…` | replace it with your base branch | Only reported when the base branch is not `master`. |
| `edited by hand since install: …` | merge each `<file>.new`, or move the change into **Persona notes** in `CONTEXT.md` and take the new file | Only happens from the second v1.1.0 install onwards, once the install manifest exists. |

Existing installs never had a manifest, so this first upgrade refreshes every tooling file as before. If you had edited an agent or script, `git diff` shows what changed; move those edits into `CONTEXT.md` (**Persona notes**) before committing.

### v1.0.0

**First release**
- `/ship`, `/pipeline-init`, `/pipeline-status`, the seven personas, the branch/tag release model and the gate.

**Added in this release — project capabilities**
- New, optional `pipeline.env` keys **`PIPELINE_HAS_DEPLOY_ENVS`** and **`PIPELINE_HAS_MARKETING`** (`yes` | `no`). See **Project capabilities** above.
- Both default to `yes`. A capability is off only when the value is exactly `no`; absent, empty or misspelt values keep the stricter, original behaviour. **No existing install changes behaviour until its owner adds a key** — `pipeline.env` is project-owned and is never rewritten by `/pipeline-init`.
- `/pipeline-init` gains `--no-deploy-envs` and `--no-marketing`. On a *fresh* install they write the declared values and, for `--no-deploy-envs`, skip creating `scripts/deploy/*` and `.github/workflows/deploy.yml` and leave the deploy keys empty. On an *existing* install nothing is ever deleted: the files are reported as kept and you are told to set the key by hand. A re-run over a project whose `pipeline.env` already declares `PIPELINE_HAS_DEPLOY_ENVS="no"` reads that declaration and does not recreate the deploy machinery, with or without `--force-tooling`.
- `promote.sh` skips the deploy wait, the staging workflow dispatch and the smoke call when there are no deployable environments, and says so. The branch/tag promotion model, the gates, sign-off and go-live are unchanged.
- The production gate asks for launch content only when the project has a marketing function **and** the ticket is `User-facing: yes`. This is the only pass/fail condition that changed.
- `gate.sh`'s PASS line and `status.sh` now report the resolved capabilities.
