---
description: Install or update the ship pipeline in the current project. Asks every question up front, then installs, connects the code host and tracker CLIs, sets up branches, tracker labels/fields/statuses and CI in one pass (never overwrites your project-specific files).
argument-hint: [--git-host H] [--git-url URL] [--base-branch B] [--staging-branch B] [--tracker T] [--tracker-url URL] [--team-key KEY] [--no-deploy-envs] [--deploy-mode merge|explicit] [--teams analysis,engineering,devops,qa,signoff]
---
The goal is that the owner answers questions once, at the start, and does nothing else except the one sign-in step
that only they can do. Work fast: detect before asking, ask everything in one go, run nothing slow. The plugin's test
suite is **not** run here; it tests the plugin, not this project.

## 1. Detect (local and quick; no questions yet)
Run these in one call and keep the results as the recommended answers:
- `git remote get-url origin` → code host (`github.com` → GitHub, a host containing `gitlab` → GitLab, `bitbucket` → Bitbucket) and, when the host is not the public service, the self-hosted base URL (`https://<host>`).
- `git symbolic-ref --short refs/remotes/origin/HEAD` (else the current branch) → trunk; `git ls-remote --heads origin` → which trunk and staging candidates (the options in step 2) already exist.
- `scripts/pipeline/pipeline.env`, if present: every key it already sets is a recommended answer (an update, not a fresh install).
- Ticket ids in recent branch names and commit subjects (`git log -200 --format=%s`, `git branch -a`) → the likely ticket prefix.

## 2. Ask everything at once
Use `AskUserQuestion` (up to four questions per call), in at most three calls, all asked before anything is installed. Put the detected answer first and mark it "(Recommended)". Skip any question that `$ARGUMENTS` already answers. "Other" always lets the owner type a value.

**Call 1**
1. **Git platform:** GitHub / GitLab / Bitbucket. If the remote is self-hosted, say so in the option description and use that URL. For a custom URL the owner picks Other and types it, e.g. `gitlab https://git.acme.com`.
2. **Branching strategy (trunk):** `main` / `master`. Merging here deploys dev.
3. **Branching strategy (staging branch):** `staging` / `stable`. Pushing here deploys qa.
4. **Ticketing platform:** Jira / Linear / GitHub Issues / GitLab Issues. Other: name it. `/pipeline-init` then checks for a CLI or API for it; if none fits, it falls back to an MCP connector (`--tracker connector`).

**Call 2** (three questions)
5. **Tracker location and ticket prefix.** One question whose options are the detected guesses, for example "Jira at https://acme.atlassian.net, prefix ABC". Other: the owner types `<url> <PREFIX>`. The URL is only needed for Jira (the site) and Linear (the workspace URL, for links); for GitHub or GitLab Issues it is the repository itself. The prefix is the searchString: `ABC` for tickets like `ABC-12`, which is the Jira project key, the Linear team key, or a prefix for issue numbers.
6. **Deployment strategy:** three options:
   - "Deploys on branch merges": merging the trunk deploys dev, pushing the staging branch deploys qa, and a tag deploys production.
   - "Explicit deploys": nothing deploys on a push, and each environment is deployed by `promote.sh` after its gate.
   - "No deployable environments".
7. **Consent** (multiSelect, four options, the first three recommended): "Set up now":
   - **Install CLIs:** install the missing ones (gh/glab/acli/jq).
   - **Branches:** create the trunk and staging branches if the remote lacks them, and protect both so the Pipeline Gate is required.
   - **Tracker:** create the labels, custom fields and statuses.
   - **Deploys on:** only if the hosts and secrets already exist.

This one answer is the owner's approval for every setup action below. Do only what they ticked, and ask nothing further.

**Call 3**
The teams are which personas run `/ship` here. Tickets arrive at the first team ticked, with the earlier work done upstream. With DevOps ticked, a later team left out hands its stage to the owner and the run goes on; without DevOps, the run ends after the last team ticked and hands the ticket to the owner. Recommend the teams in an existing `pipeline.env` (`bash scripts/pipeline/teams.sh`), else all of them.
8. **Teams: plan and build** (multiSelect):
   - **Analysis** (Product Owner & Business Analyst, always together): tickets arrive as requirements.
   - **Engineering** (Senior Engineer): builds the code and its tests.
9. **Teams: ship** (multiSelect):
   - **DevOps**: merges and promotes the build to dev, qa, staging and production.
   - **QA** (QA Tester): tests the build on qa. Brings DevOps.
   - **Sign-off** (App Specialist): checks it on staging against the release checklist. Brings DevOps.

   Before installing, pass the ticked teams through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline/teams.sh" --normalize '<teams>'` and tell the owner in one line about any team it added (QA or Sign-off without DevOps). No team ticked in either question: ask 8 and 9 again.
10. **Environment URLs** (only when the project has environments). Offer the detected or guessed pattern (`https://dev.<app>…`). Other: the owner types dev, qa, staging and production URLs and the health path, space-separated.

If a Jira URL was given, resolve its cloudId now: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline/connect.sh" cloud-id <url>`.

## 3. Install (one run, seconds)
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh"` from the repository root with every answer as a flag:
- `--git-host`, `--git-url`, `--base-branch`, `--staging-branch`
- `--tracker`, `--tracker-url`, `--tracker-cloud-id`, `--team-key`
- `--no-deploy-envs` or `--deploy-mode merge|explicit`, `--teams <the teams ticked in 8 and 9, comma-separated>`
- `--dev-url --qa-url --staging-url --production-url --health-path`
- `--create-branches` when "Branches" was ticked

Then relay the output:
- If it prints `ACTION:` (an existing `.gitlab-ci.yml` with its own `include:` list, or an existing `bitbucket-pipelines.yml`), make that merge yourself now: show the owner the resulting diff in your final message, not as a question.
- Files listed as **customised, kept** are tooling files the owner edited by hand. Show the difference against each `.new` and keep theirs for now; list them in the final message. Never pass `--force-tooling` without their say-so.

## 4. Connect the CLIs (CLIs, not MCP connectors)
1. If "Install CLIs" was ticked: `bash scripts/pipeline/connect.sh install`. It uses winget, brew, apt or dnf, or the vendor download for acli. Report any `FAILED` line with its manual command.
2. Run `bash scripts/pipeline/connect.sh status`. Exit 4 means a sign-in is missing.
3. **The one owner step.** Every sign-in is a browser flow or a token that only the owner may type, so ask for it once, in one message:
   > Run `bash scripts/pipeline/connect.sh login` in a terminal. It signs you in to <the tools listed> and stores any tokens in your user config directory (mode 600), outside the repo. Tell me when it's done.

   If this session can open a terminal tab for the owner, open one in the project directory. Never ask for a token in the chat, and never type one yourself. Keep working on step 6 while you wait; step 5 needs the sign-in.
4. When the owner is back, re-run `connect.sh status` until every tool reads ready.

## 5. Set up the host and the tracker (only what was ticked)
- Always `bash scripts/pipeline/tracker.sh check`; when "Tracker" was ticked, also `bash scripts/pipeline/tracker.sh setup` (else `setup --check`, to report what is missing).
  - It creates the labels, label groups, custom fields and statuses in `scripts/pipeline/tracker-schema.txt`. It maps pipeline states onto the tracker's statuses, and writes `scripts/pipeline/tracker.map`.
  - Relay each `CREATED`, `MAPPED` and `NOTE` line.
  - A Jira status it creates still has to be added to the project's workflow before it is used. Until then it is mapped to the nearest existing status, so nothing blocks.
  - With `TRACKER=connector`, do the same through the connector's tools instead.
- Branch protection ("Branches"): `bash scripts/pipeline/host.sh protect <trunk>` and `… protect <staging>`. A refusal (for example HTTP 403 on a free private GitHub repository) is not a failure: report it with the enforcement mode from `bash scripts/pipeline/enforcement.sh`.
- "Deploys on": `bash scripts/pipeline/host.sh var-set PIPELINE_DEPLOY_ENABLED true`.

## 6. Fill in the project files (while waiting on the sign-in)
- If `docs/pipeline/CONTEXT.md` was just created, fill it in by inspecting the repository (build files, README, architecture docs):
  - product summary, stack, and the exact test and build commands;
  - environments, architecture rules and high-risk areas;
  - brand and audience, regulatory notes.

  Record the answers from step 2 in prose (host, branches, tracker, deploy strategy, teams). Ask only what the repository cannot tell you, and do it in the step-2 questions if you can foresee it.
- If `RELEASE_CHECKLIST.md` was just created, tailor it to this project (keep the Tickets, Security, Data and Infrastructure sections).

## 7. Upgrading an existing install
Project-owned files are never rewritten, so an older install keeps its old `pipeline.env` and CI files.
1. Run `bash scripts/pipeline/doctor.sh --offline` and take each finding marked `[upgrade: …]`:
   - **CI files:** show the diff between the owner's file and the plugin template, rendered with their branch names, and propose only the hunks that fix the finding. Their file may carry deliberate changes.
   - **`pipeline.env`:** propose the exact lines, including any new keys (`GIT_HOST`, `GIT_HOST_URL`, `TRACKER_URL`, `TRACKER_CLOUD_ID`, `DEPLOY_MODE`, `PIPELINE_TEAMS` in place of `PIPELINE_START_LEVEL`) that match the step-2 answers.
2. Apply each change only after the owner says yes, then re-run the doctor. Anything they decline stays as a warning.

## 8. Check and commit
1. Run `bash scripts/pipeline/doctor.sh`. It takes seconds and checks the files, `pipeline.env`, git, the host, CI and the tracker through its CLI. Install is not "done" while it reports a FAIL.
2. Commit with the message `chore: install ship pipeline`. The guard hook blocks an agent's push of that commit to the trunk, because it has no ticket. Push a branch and open a pull request for the owner to mark as `infra` and merge (a label on GitHub and GitLab; on Bitbucket the owner pushes the branch as `infra/…`). Or let the owner push it from their own terminal.

Reply with only:
- **What was done:**
  - the answers used (host, URL, branches, tracker, prefix, deploy strategy, teams);
  - files created, updated or kept;
  - CLIs installed and signed in;
  - tracker items created or mapped;
  - branches created or protected.
- **Impact:** the doctor's result (ready yes/no), the enforcement mode, and anything left that only the owner can do (hosts and deploy secrets, a Jira workflow edit, a declined item).
