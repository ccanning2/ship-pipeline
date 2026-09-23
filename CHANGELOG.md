# Changelog

Each release in one section, newest first. Upgrading notes sit under the release that needs them.

## v3.0.0

The personas regroup into four teams, a project chooses the level where its tickets start, each code host and tracker is a single adapter file, and the README is rewritten.

- **Four teams and a start level.**
  - The teams are analysis (product owner + business analyst), engineering (senior engineer), devops (new) and QA (qa-tester + app specialist).
  - `PIPELINE_START_LEVEL` (`/pipeline-init` asks; `init.sh --start-at`) says where `/ship` picks a ticket up. At a later level the ticket arrives with the upstream teams' work done: analysed for engineering, built for devops, or already on qa.
  - `scripts/pipeline/handover.sh` records that work at intake, so every gate stays exactly as strict.
- **DevOps persona.** Promotion leaves the senior engineer.
  - The engineer builds and hands over (Stage: dev, Owner: devops).
  - `devops` merges to dev, checks it there (`dev-check.md`), and promotes the same sha to qa, staging and the production tag. It rolls back, and owns CI/CD, deploy scripts and infrastructure (write-restricted to those by `allow-paths.sh`).
  - QA hands a passed build to devops. The tracker gains the Owner label `devops`.
- **Plan mode for the analysis team.**
  - `product-owner` and `business-analyst` run with `permissionMode: plan`. They read and return a plan: the files they would write and the ticket commands they would run.
  - `/ship` applies the plan after checking each path.
  - Hooks back this up when plan mode is not honoured: no file writes, and only `tracker.sh view|children` (the new `allow-commands.sh script:verb,verb` form).
- **Removed: the market researcher and marketing specialist.**
  - Gone with them: the research and marketing stages, `research.md` / `marketing.md`, the production marketing gate, `PIPELINE_HAS_MARKETING`, `--no-marketing` and the init question.
  - The tracker schema drops the Stage label `research`, the Owner labels `market-researcher` and `marketing`, and the kind `marketing`. A `marketing` row in an older `tickets.md` still reads as a known kind.
- **One adapter per platform.**
  - `scripts/pipeline/adapters/host-{github,gitlab,bitbucket}.sh` and `tracker-{jira,linear,github,gitlab,connector}.sh` share `scripts/pipeline/lib/*-common.sh`.
  - `init.sh` installs only the pair for the chosen platforms, as `host.sh` and `tracker.sh`. The doctor fails when an installed adapter no longer matches `GIT_HOST` / `TRACKER`.
  - A platform flag that disagrees with a kept `pipeline.env` prints the line to change.
- **A status board instead of a transcript.**
  - `scripts/pipeline/board.sh` shows, in about fifteen lines: every stage (done, current, waiting, skipped), who holds the ticket and what they are doing, the sha in each environment, open defects and the last handoffs.
  - `/ship` records who is busy (`board.sh <T> now`) and each handoff (`board.sh <T> handoff <from> <to> '<reason>'`). After each stage it shows only the board, never the personas' reasoning or tool output.
  - `--watch` redraws it live; `--pane` opens it in a tmux side pane; `--all` lists the tickets in flight.
  - `/pipeline-status` leads with it. The live activity log is kept out of git (`.claude/.pipeline-activity/`).
- **Retired tooling is removed.** A file an earlier install put in place that this version no longer ships (a removed persona or template, the adapter of a platform no longer chosen, the old test-suite copy) is deleted when it is still exactly as installed. A copy the owner edited is kept and reported.
- **Fixes from a trial `/pipeline-init` run:**
  Fixes found by running `/pipeline-init` on a fresh test repository:
  - **winget installs work on Windows.** winget puts portable packages such as jq and glab under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, and not always on `PATH`, so `connect.sh install` reported them installed although they could not be run. It now copies the exe into `~/bin` and reports `INSTALLED` only once the tool is found. A re-run no longer fails because winget says the package is already installed.
  - **One clear tracker error.** A missing Linear key or Jira token or site is now reported once, before any API call, instead of being followed by a misleading "no team with key …".
  - **Placeholder URLs.** The doctor flags only the `.example.invalid` placeholders that init writes, not real URLs that contain "example".
  - **Staging branch advice.** The doctor's missing-staging-branch advice now points at `/pipeline-init`'s Branches option.
- **Docs.** The README is now a short guide (install, set up, use, how it works, the file map); these notes moved here.

### Upgrading from v2
Run `/pipeline-init`. It refreshes the tooling, installs the two adapters for your `GIT_HOST` and `TRACKER`, adds the `devops` persona, and removes the retired personas and templates you have not edited. `pipeline.env` is still never rewritten; `/pipeline-init` proposes the lines to change:
- Add `PIPELINE_START_LEVEL="analysis"`. Without it the start level is `analysis`, the v2 behaviour.
- Delete `PIPELINE_HAS_MARKETING`. It is ignored now.

Then:
- Create the new Owner label: `bash scripts/pipeline/tracker.sh setup`.
- A ticket in flight with Stage `research` continues at product; one waiting on the marketing persona continues at go-live.

## v2.0.0

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

### Upgrading from v1.1.0
Run `/pipeline-init`. Tooling refreshes as before, and `pipeline.env` is still never rewritten. A v1.1.0 `pipeline.env` without the new keys behaves exactly as it did before: `GIT_HOST` defaults to `github`, `TRACKER` to `linear` and `DEPLOY_MODE` to `merge`. Add `GIT_HOST`, `GIT_HOST_URL`, `TRACKER_URL`, `TRACKER_CLOUD_ID` and `DEPLOY_MODE` when you want to change them; `/pipeline-init` proposes the lines. Then:
- Run `bash scripts/pipeline/connect.sh login` once.
- Run `bash scripts/pipeline/tracker.sh setup --check` to see whether the tracker workspace already matches.
- Delete the `self-test` step from your installed `pipeline-gate.yml`: there is no longer a suite in the project to run.

## v1.1.0

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

### Upgrading from v1.0.0

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

## v1.0.0

**First release**
- `/ship`, `/pipeline-init`, `/pipeline-status`, the seven personas, the branch/tag release model and the gate.

**Added in this release — project capabilities**
- New, optional `pipeline.env` keys **`PIPELINE_HAS_DEPLOY_ENVS`** and **`PIPELINE_HAS_MARKETING`** (`yes` | `no`). See **Project capabilities** above.
- Both default to `yes`. A capability is off only when the value is exactly `no`; absent, empty or misspelt values keep the stricter, original behaviour. **No existing install changes behaviour until its owner adds a key** — `pipeline.env` is project-owned and is never rewritten by `/pipeline-init`.
- `/pipeline-init` gains `--no-deploy-envs` and `--no-marketing`. On a *fresh* install they write the declared values and, for `--no-deploy-envs`, skip creating `scripts/deploy/*` and `.github/workflows/deploy.yml` and leave the deploy keys empty. On an *existing* install nothing is ever deleted: the files are reported as kept and you are told to set the key by hand. A re-run over a project whose `pipeline.env` already declares `PIPELINE_HAS_DEPLOY_ENVS="no"` reads that declaration and does not recreate the deploy machinery, with or without `--force-tooling`.
- `promote.sh` skips the deploy wait, the staging workflow dispatch and the smoke call when there are no deployable environments, and says so. The branch/tag promotion model, the gates, sign-off and go-live are unchanged.
- The production gate asks for launch content only when the project has a marketing function **and** the ticket is `User-facing: yes`. This is the only pass/fail condition that changed.
- `gate.sh`'s PASS line and `status.sh` now report the resolved capabilities.
