# SHI-45 — Requirements (engineer-ready)

Status: approved
Traces to: product.md (US-1..US-6, R1..R8)

`/pipeline-init` opens the install pull request and merges it into the trunk itself. It does this through one
dedicated route, `scripts/pipeline/install-merge.sh`. The guard hook (`scripts/pipeline/hooks/guard-merge.sh`) lets that
route through only after it has checked, from the commit itself, that the request is nothing but the pipeline's own
install. Every other agent push or merge is decided exactly as today.

Terms used below:
- **trunk**: `BASE_BRANCH`; **staging branch**: `STAGING_BRANCH`; **remote**: `PIPELINE_REMOTE` (default `origin`).
- **install branch**: the reserved branch name `ship-pipeline/install`. It has no digits, so it never matches a
  ticket id. It is not `infra/*`, so it never means "infra" on Bitbucket. It is a label only, never the proof.
- **install commit**: `HEAD` when the route runs.
- **trunk tip**: the local remote-tracking ref `<remote>/<trunk>`. The guard does not use the network.
- **install diff**: `git diff --no-renames <trunk tip> <install commit>`, as added / modified / deleted paths plus
  their blob contents at the install commit. A rename counts as a delete plus an add.
- **reference**: the ship pipeline plugin as installed in Claude Code for this user. It is the plugin root that
  `/pipeline-init` runs from as `${CLAUDE_PLUGIN_ROOT}`. See FR-4 for how it is found.
- **declared configuration**: `GIT_HOST`, `TRACKER`, `BASE_BRANCH`, `STAGING_BRANCH`, `DEPLOY_MODE`, `PIPELINE_HAS_DEPLOY_ENVS`
  as written in `scripts/pipeline/pipeline.env` at the install commit. Missing keys get the defaults
  `scripts/init.sh` uses: DEPLOY_MODE=merge; PIPELINE_HAS_DEPLOY_ENVS is on unless exactly `no`.
- **rendered**: a file transformed the way `scripts/init.sh` transforms it for the declared configuration:
  - branch placeholders are filled in docs and CI files;
  - `#@on-merge` lines are kept or dropped by deploy mode in CI files;
  - scripts, agents and `.claude/settings.json` are copied verbatim.
  Two files that differ only in CR characters count as identical, as they do in `init.sh`.

## Functional requirements
- FR-1 (US-1, R1a): A new tooling script, `scripts/pipeline/install-merge.sh`, is the only init route. It has exactly
  two forms:
  - `install-merge.sh`: verify, push, open or reuse the request, merge.
  - `install-merge.sh --open-only`: push and open or reuse the request, never merge.
  Any other argument is a usage error (exit 1) and does nothing. `scripts/init.sh` classifies it as **tooling**:
  it is installed, recorded in `.install-manifest` and made executable, and it is listed in the header comment's
  tooling list.
- FR-2 (R1b, R1d): The route requires the current local branch to be the install branch. It pushes `HEAD` to
  `refs/heads/ship-pipeline/install` on the remote, never with force. It targets the trunk only. It never pushes,
  moves or deletes the staging branch, a tag, or any ref other than the install branch.
- FR-3 (R1c): **The proof.** A request is init's install only if every one of these checks passes on the install
  commit (the blob contents at that commit, not the working tree):
  1. The trunk tip exists and is an ancestor of the install commit, and the install diff is not empty.
  2. `BASE_BRANCH` in the committed `pipeline.env` equals the trunk the guard reads from the working tree.
  3. Every added or modified path belongs to the **install set** for the declared configuration, and its content
     meets its class:

     | Class | Paths (only those `init.sh` installs for the declared configuration) | Content rule |
     |---|---|---|
     | T: tooling | every tooling destination in `init.sh`. Includes `scripts/pipeline/*.sh` in its tooling loop (with `install-merge.sh`), `host.sh` (= `adapters/host-<GIT_HOST>.sh`), `tracker.sh` (= `adapters/tracker-<TRACKER>.sh`), `lib/host-common.sh`, `lib/tracker-common.sh` (not for connector), `tracker-schema.txt`, `hooks/*.sh`, `.claude/agents/<each agents/*.md>`, `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md`, `docs/pipeline/_templates/<each template>` | identical to the reference copy, rendered |
     | S: safety-bearing project files | `.claude/settings.json`; the host's CI files (`.github/workflows/pipeline-gate.yml`, `deploy.yml` when deploy envs are on; `.gitlab/pipeline-gate.yml`, `.gitlab/pipeline-deploy.yml`; `bitbucket-pipelines.yml` or `bitbucket-pipelines.ship.yml` from the matching template); `scripts/deploy/{deploy,rollback,smoke}.sh` when deploy envs are on; any `<T or S path>.new` | identical to the reference template or file, rendered. A `.new` file matches the reference copy of the file it sits beside |
     | G: `.gitlab-ci.yml` (GitLab only) | `.gitlab-ci.yml` | either a new file that is exactly what `init.sh` generates when none exists, or the trunk tip's version followed by exactly the `# ship-pipeline` include block `init.sh` appends. Any other change, including an edit to an existing `include:` list, fails |
     | F: free project files | `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md`, `docs/pipeline/README.md`, `scripts/pipeline/pipeline.env`, `.gitignore`, `scripts/pipeline/.install-manifest` | any content |

  4. Every deleted path is one `init.sh` retires. That means a path under `scripts/pipeline/`, `.claude/agents/`,
     `docs/pipeline/_templates/`, `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md` or `tests/pipeline/` that is **not** in
     the current install set, or `.gitignore.pipeline`. Any other deletion fails.
  5. A change to the file mode alone on a path in the install set is accepted. Symlinks, submodules and any path
     outside the install set fail.
- FR-4 (R1 "never trust what the command says"): The guard reads the reference from Claude Code's own record of
  the installed plugin, or from the hook process's own environment (set when Claude Code was started, like
  `PIPELINE_BYPASS`). It never takes it from the command's words, a variable assignment in the command, a file in the
  repository, or a marker file. If the reference cannot be found, or two recorded installs disagree, the check fails
  closed. Tests point the reference at a fixture the same way they pass `CLAUDE_PROJECT_DIR` today, through the hook's
  own environment.
- FR-5 (R1, US-2): **Guard recognition.** A simple command whose program is `install-merge.sh` is examined, using the
  same parsing and wrapper look-through as today (`bash -c`, `sudo`, `env`, `xargs`, `eval`, `timeout`…). The guard
  allows it only when all of these hold:
  - a. the invoked path resolves to the project's `scripts/pipeline/install-merge.sh`;
  - b. the arguments are none, or exactly `--open-only`;
  - c. the files the route relies on are identical to the reference, in the working tree: `install-merge.sh`,
    `host.sh`, `lib/host-common.sh`, `base-ref.sh`, `ticket-id.sh`, and `hooks/guard-merge.sh` itself;
  - d. the merge form only: the current branch is the install branch and FR-3 passes.

  When any check fails, the guard blocks (exit 2) and names the first failing check and path (copy below). It never
  asks for a ticket for this command. Other segments of the same command line are checked as today.
- FR-6 (R1a, R6): Every existing route stays gated exactly as today, including from the install branch:
  - `git push` / `git merge` into the trunk or staging;
  - `gh pr merge`, `glab mr merge`;
  - API merges and ref and tag writes;
  - `host.sh merge|set-ref`;
  - force pushes, deletes and bulk pushes;
  - the `infra` label and Bitbucket `infra/` branches;
  - version tags.

  The install branch name, a marker file, `PIPELINE_TICKET` and any flag grant nothing outside FR-5. `PIPELINE_BYPASS=1`
  in Claude Code's own environment still lets any command through, including the route, and the bypass is announced.
- FR-7 (US-1, R4): **Route, merge form.** The route runs the FR-3 check itself before anything else (defence in
  depth, and a guard for a run from the owner's terminal). Then it:
  1. pushes the install branch (FR-2);
  2. reuses an open request from the install branch into the trunk, or opens one. Title: `chore: install ship pipeline`
     on a first install, `chore: update ship pipeline to v<reference version>` when the trunk tip already has
     `scripts/pipeline/.install-manifest`. Body: FR-14 copy;
  3. merges it **at the install commit's sha**. GitHub and GitLab pass the sha to the merge call. On Bitbucket the
     route re-reads the request's source commit right before merging and refuses when it is not the install commit.
     All three hosts go through `host.sh`, so every adapter (github, gitlab, bitbucket) is covered.

  The route may wait, bounded by `PIPELINE_WAIT_TRIES`, while the host is still working out whether the request can
  be merged. It never re-sends a merge the host refused.
- FR-8 (US-1, US-6): After a successful merge the route:
  - fetches the trunk, switches the working tree to the trunk and fast-forwards it to the remote trunk;
  - deletes the install branch on the remote and locally (US-6, Could). If the deletion fails, that is a `NOTE`,
    not a failure.
- FR-9 (R2, US-3): **Host refusal.** Any refusal by the host ends the route with exit 3 and one line:
  `REFUSED <request url> <reason>`. Refusals include a required review, a required check, rulesets, missing permission,
  a rejected push, a source-commit mismatch, or an API that Bitbucket Data Center lacks. The route never:
  - uses an admin or bypass merge;
  - reads or changes branch protection or rulesets;
  - adds, removes or requests any label;
  - retries through another route;
  - force-pushes.

  If no request could be opened, `<request url>` is the host's web URL for the repository.
- FR-10 (R2, US-3): **Route, open-only form.** `--open-only` pushes the install branch and opens or reuses the
  request, exactly as FR-7 steps 1–2. It prints `OPENED <request url>` and never merges. `/pipeline-init` uses it as the
  fallback when the guard or the route's own check refuses the merge form.
- FR-11 (R5, US-4): Call 2, question 7 still has four options. "Branches" becomes: create the branches, merge the
  install request without a human review, then protect both (copy below). With "Branches" unticked, step 8 is
  today's text and flow, unchanged, and the route is not run.
- FR-12 (R3): With "Branches" ticked, `/pipeline-init` runs, in this order:
  1. doctor;
  2. create the local install branch from the trunk tip and commit only the install's files on it (the files
     `init.sh` reported, CONTEXT.md, RELEASE_CHECKLIST.md, and any `ACTION:` CI merge);
  3. run the route;
  4. only then `host.sh protect <trunk>` and `protect <staging>`, as today, whatever the merge outcome;
  5. `enforcement.sh`.
  The Pipeline Gate's pass/fail conditions (`ci-gate.sh`, `pipeline-gate.yml`, `gate.sh`) do not change.
- FR-13 (US-5): A re-run (upgrade) follows the same flow and route. Where the host already requires the gate or a
  review, FR-9 applies.
- FR-14 (R7, R8): The docs say that init merges its own install request **without a human review**. They say it falls
  back to the owner when the host or the guard refuses, and that a team that wants a review leaves "Branches" unticked
  or keeps a required review on the trunk. The docs covered are:
  - `docs/pipeline/BRANCHING.md` and `template/docs/pipeline/BRANCHING.md` ("Repository maintenance without a ticket");
  - `commands/pipeline-init.md` step 8;
  - README (the "Work without a ticket" paragraph and the hooks line);
  - CHANGELOG (new `v3.2.0` section);
  - the guard's block message.
  No doc says the install is reviewed. `.claude-plugin/plugin.json` version becomes `3.2.0` (minor: a new tooling path,
  no renames).
- FR-15 (R6): `/ship` never uses the route. `commands/ship.md`, `agents/*.md` and `.claude/agents/*.md` do not name
  `install-merge`.
- FR-16 (US-3): The final reply of `/pipeline-init` reports the merge outcome under **Impact**. That is either
  `Install merged into <trunk>: <url>` or the fallback line (copy below), along with the doctor result and the
  enforcement mode as today.

## Non-functional requirements
- NFR-1 (safety, high-risk area): Fail closed. Any error, missing tool, missing ref or unreadable blob during the
  FR-3/FR-5 checks blocks the route. It never allows it.
- NFR-2 (performance): The guard's cost for every command other than `install-merge.sh` stays as today: no extra
  process per call beyond today's. For the route, the check uses no network and finishes within a few seconds on
  Windows Git Bash for a full install diff (~70 files). Batch the checksums the way `init.sh` does.
- NFR-3 (portability): bash 3.2 (macOS), Git Bash on Windows, GNU and BSD tools, CRLF checkouts. No new runtime
  dependency. `jq` stays optional in the guard, as today.
- NFR-4 (idempotency): Re-running the route after a successful merge makes no change and exits 1 with "nothing to
  merge". Re-running it with an open request reuses that request.
- NFR-5 (no secrets): The route prints URLs and reasons only, never tokens or API payloads.
- NFR-6 (tests): Fixtures only, under `mktemp -d`. Host calls go through the existing test doubles
  (`PIPELINE_GH_CMD`, `PIPELINE_GLAB_CMD`, `PIPELINE_CURL_CMD`). No network.

## Data model changes
| Entity/table | Change | Constraints/indexes | Migration notes |
|---|---|---|---|
| (files) `scripts/pipeline/install-merge.sh` | new tooling file | executable; in `.install-manifest` | installed on the next `/pipeline-init` re-run; not destructive |
| (git) branch `ship-pipeline/install` | reserved name | never force-pushed; deleted after merge | none |

## CLI contract
| Command | Who | Request | Output / exit | Errors | Breaking? |
|---|---|---|---|---|---|
| `bash scripts/pipeline/install-merge.sh` | `/pipeline-init` only (agent, through the guard), or the owner's terminal | no args; current branch = install branch | `MERGED <url>` then optional `NOTE <text>` lines; exit 0 | 1 usage / nothing to merge / no remote; 3 `REFUSED <url> <reason>`; 4 `NOT-INSTALL <path>: <reason>` (own check, before any push) | no (new) |
| `bash scripts/pipeline/install-merge.sh --open-only` | `/pipeline-init` fallback | as above | `OPENED <url>`; exit 0 | 1; 3 `REFUSED <url> <reason>` | no |
| guard, route segment | hook | the Bash tool call | exit 0 allow; exit 2 block with message | n/a | no |
| guard, every other segment | hook | as today | unchanged decisions | unchanged | no |

## UI changes (owner-facing copy)
| Where | Change | States | Copy |
|---|---|---|---|
| `/pipeline-init` Call 2 q7, "Branches" | wording | ticked by default | **Branches:** create the trunk and staging branches if the remote lacks them, merge the install pull request (no human review), then protect both so the Pipeline Gate is required. |
| `/pipeline-init` Impact, merged | new line | success | `Install merged into <trunk>: <url>` |
| `/pipeline-init` Impact, fallback | new line | host or guard refused | `Install pull request not merged (<reason>). Open <url>, mark it infra and merge it (on Bitbucket, push the branch as infra/<name>).` |
| guard block, route refused | new message | block | `PIPELINE GATE: blocked '<segment>' (install route): <reason>. This route merges only the pipeline's own install: every changed file must be one that scripts/init.sh installs, and each tooling file must match the plugin's copy. Way forward: run 'bash scripts/pipeline/install-merge.sh --open-only' and leave the request for the owner to mark infra and merge. Do not try to get around this hook.` |
| guard block, reasons (`<reason>`) | new | block | `<path> is not part of the install` · `<path> differs from the plugin's copy` · `<path> is deleted but is not retired tooling` · `the current branch is '<b>', not 'ship-pipeline/install'` · `<remote>/<trunk> is missing or not an ancestor of HEAD` · `nothing to merge` · `the plugin's installed copy could not be found` · `the route must be run as scripts/pipeline/install-merge.sh` · `unexpected argument '<a>'` · `<file> (used by the route) differs from the plugin's copy` |
| guard `no_ticket` message | one line added under "Ways forward" | block | `  - The pipeline's own install or upgrade: /pipeline-init merges it through scripts/pipeline/install-merge.sh, which accepts nothing but the plugin's own files.` |
| PR/MR body | new | on open | `Ship pipeline install, opened and merged by /pipeline-init without a human review. Every file matches the plugin's copy or is a project file init.sh scaffolds (docs/pipeline/BRANCHING.md).` |

## Permissions matrix
| Action | Agent via `install-merge.sh` | Agent via any other route | `/ship` / personas | Owner's own terminal | `PIPELINE_BYPASS=1` (Claude Code env) |
|---|---|---|---|---|---|
| Ticketless merge of a verified install into the trunk | allowed | blocked (as today) | never used | allowed (the route's own check still runs) | allowed, announced |
| Ticketless merge of anything else into the trunk | blocked | blocked | blocked | not gated (as today) | allowed, announced |
| Staging branch / tag / force / delete / bulk push | never (route cannot) | as today | as today | not gated | allowed, announced |
| Add `infra` label / push Bitbucket `infra/` | never | blocked | blocked | owner's decision | allowed, announced |
| Change branch protection / rulesets / admin merge | never | not added by this ticket | never | owner's decision | n/a |

## Acceptance criteria
Guard, positive (in `tests/pipeline/test_guard_merge.sh`. The fixture install is produced by running `REPO_SRC/scripts/init.sh` into a fixture repo with the reference = `REPO_SRC`, committed on `ship-pipeline/install` on top of `origin/master`)
- AC-1 (FR-3, FR-5): Given a fresh GitHub install commit with CONTEXT.md and RELEASE_CHECKLIST.md filled in, when the agent runs `bash scripts/pipeline/install-merge.sh`, then the guard exits 0.
- AC-2 (FR-3): Given fresh install commits for gitlab (no existing `.gitlab-ci.yml`), bitbucket, `--no-deploy-envs` and `--deploy-mode explicit`, when the route runs, then each is allowed.
- AC-3 (FR-3 G): Given a GitLab repo whose trunk `.gitlab-ci.yml` has no `include:`, when the install commit adds exactly init's appended block, then it is allowed.
- AC-4 (FR-3): Given an install commit whose tooling files differ from the reference only in CR line endings, or only in file mode, then it is allowed.
- AC-5 (FR-3, FR-13): Given an upgrade commit that updates tooling, deletes a retired tooling file still as installed, and adds a `<tooling>.new` identical to the reference copy, then it is allowed.
- AC-6 (FR-5): Given the allowed install of AC-1, when the command is `bash -c "bash scripts/pipeline/install-merge.sh"` or `./scripts/pipeline/install-merge.sh`, then it is allowed.
- AC-7 (FR-5, FR-10): Given any branch and any diff, when the command is `bash scripts/pipeline/install-merge.sh --open-only` and FR-5c holds, then it is allowed.

Guard, negative: R1 (each blocked with exit 2, and the message names the reason and path)
- AC-8 (FR-3): Given the AC-1 install plus `src/app.js`, when the route runs, then it is blocked: `src/app.js is not part of the install`.
- AC-9 (FR-3 T): Given the AC-1 install with `scripts/pipeline/hooks/guard-merge.sh` edited, then blocked: `differs from the plugin's copy`. The same applies to `hooks/allow-paths.sh`, `gate.sh` and `check-signoff.sh`, one case each.
- AC-10 (FR-3 S): Given `.claude/settings.json` with the guard hook entry removed, then blocked.
- AC-11 (FR-3 S): Given `.github/workflows/pipeline-gate.yml` edited, then blocked. The same applies to `.gitlab/pipeline-gate.yml` and `bitbucket-pipelines.yml` in their host fixtures.
- AC-12 (FR-3 T): Given `GIT_HOST="github"` and `host.sh` equal to the gitlab adapter, then blocked.
- AC-13 (FR-3 G): Given a GitLab trunk `.gitlab-ci.yml` with its own `include:` list edited by the install commit, then blocked.
- AC-14 (FR-3 del): Given an install commit that deletes `scripts/pipeline/gate.sh`, or `.claude/settings.json`, then blocked: `is deleted but is not retired tooling`.
- AC-15 (FR-3): Given an extra `.claude/agents/extra.md` or `docs/pipeline/_templates/extra.md`, then blocked.
- AC-16 (FR-3.1): Given `origin/master` missing, or not an ancestor of HEAD, then blocked. Given HEAD equal to `origin/master`, then blocked: `nothing to merge`.
- AC-17 (FR-3.2): Given the committed `pipeline.env` saying `BASE_BRANCH="main"` while the working tree says `master`, then blocked.
- AC-18 (FR-5d): Given the AC-1 install committed on `chore/install` (not the install branch), then blocked.
- AC-19 (FR-5a): Given a copy of the route at `/tmp/x/install-merge.sh` or `scripts/other/install-merge.sh`, when that path is run, then blocked: `the route must be run as scripts/pipeline/install-merge.sh`.
- AC-20 (FR-5b): Given `install-merge.sh --force`, `install-merge.sh master`, or `install-merge.sh --open-only x`, then blocked: `unexpected argument`.
- AC-21 (FR-5c): Given the working-tree `install-merge.sh` or `lib/host-common.sh` edited, when either form runs, then blocked.
- AC-22 (FR-4): Given no reference reachable from the hook's environment, when the route runs, then blocked: `the plugin's installed copy could not be found`.
- AC-23 (FR-4): Given an edited `guard-merge.sh` in the install commit, and a reference location or fake plugin root given in the command (an argument, `VAR=… bash scripts/pipeline/install-merge.sh`, or a file under the project such as `.claude/.pipeline-init`), then the guard still compares against the true reference and blocks.

Guard, negative: R6 (unchanged guarantees)
- AC-24 (FR-6): Given the change, when `bash tests/pipeline/run-all.sh` runs, then every existing case in `test_guard_merge.sh` and in the guard section of `test_adapters.sh` passes with its existing expected exit code. `git diff master -- tests/pipeline/test_guard_merge.sh tests/pipeline/test_adapters.sh` shows only added lines.
- AC-25 (FR-6): Given the current branch is `ship-pipeline/install` with a valid install commit and no ticket, then each of these is blocked (exit 2) and names `no ticket id`: `git push origin HEAD:master`; `git push`; `gh pr merge 5 --merge`; `gh api -X PUT repos/o/r/pulls/5/merge`; `glab mr merge 5`; `bash scripts/pipeline/host.sh merge ship-pipeline/install master x`.
- AC-26 (FR-6): Given the install branch, then `git push origin HEAD:staging`, `git push origin v1.0.0`, `git push --force origin HEAD:master`, `git push --all origin`, `gh pr edit 5 --add-label infra` and, on bitbucket, `git push origin HEAD:infra/x` are blocked as today.
- AC-27 (FR-6): Given `bash scripts/pipeline/install-merge.sh && git push origin HEAD:master` on a valid install, then the command is blocked because of the push segment.
- AC-28 (FR-6): Given `PIPELINE_BYPASS=1` in the hook's environment and an invalid install, when the route runs, then it is allowed and the bypass is announced. Given `PIPELINE_BYPASS=1` written into the command, then it is still blocked.
- AC-29 (FR-6, FR-14): Given a ticketless `git push` on master, then the block message still contains `'infra' label`, `own terminal` and `Do not try to get around`, and now also `install-merge.sh`.
- AC-30 (FR-15): `commands/ship.md`, `agents/*.md` and `.claude/agents/*.md` do not contain `install-merge`.

Route (with `PIPELINE_GH_CMD` / `PIPELINE_GLAB_CMD` / `PIPELINE_CURL_CMD` fakes that log every call; `PIPELINE_WAIT_TRIES=1`)
- AC-31 (FR-7): Given a GitHub fixture with a valid install on the install branch, when `install-merge.sh` runs, then it:
  - pushes `ship-pipeline/install` without force;
  - opens a request with head `ship-pipeline/install`, base `master` and title `chore: install ship pipeline`;
  - merges with `sha=<install commit>`;
  - prints `MERGED <url>` and exits 0.
- AC-32 (FR-7): The same for GitLab (MR merge with `sha`) and Bitbucket (the source commit is re-read, then the merge is called).
- AC-33 (FR-7): Given an open request from the install branch already exists, then it is reused and none is created.
- AC-34 (FR-7): Given the trunk tip already contains `.install-manifest`, then the title is `chore: update ship pipeline to v<reference version>`.
- AC-35 (FR-9): Given the fake host rejects the merge (GitHub 405 "required status check", GitLab 405/406, Bitbucket 400/403), then the route:
  - exits 3 with exactly one `REFUSED <url> <reason>` line;
  - makes no second merge call;
  - makes no call containing `protection`, `rulesets`, `protected_branches`, `branch-restrictions`, `labels`, `--admin` or `bypass`.
- AC-36 (FR-9): Given Bitbucket reports a source commit other than the install commit, then there is no merge call and the route exits 3.
- AC-37 (FR-9, FR-2): Given the remote rejects the push of the install branch, then the route exits 3, never retries with force, and makes no merge call.
- AC-38 (FR-7, FR-3): Given the install commit adds `src/app.js`, when the route is run directly (without the hook), then it exits 4 `NOT-INSTALL src/app.js: …` before any push or host call.
- AC-39 (FR-8): Given a successful merge, then:
  - the working tree is on `master` at the remote trunk;
  - the install branch is deleted on the remote and locally;
  - a failed delete gives a `NOTE` line and still exit 0.
- AC-40 (FR-10): Given `--open-only`, then the route pushes and opens or reuses the request, prints `OPENED <url>`, exits 0, and makes no merge call.
- AC-41 (FR-2, FR-1): The route's host call log never names the staging branch, a `refs/tags/` ref or a force flag, and any argument other than `--open-only` exits 1 with no calls.
- AC-42 (NFR-4): Given a second run after AC-31, then exit 1 with `nothing to merge` and no host call.

Init and docs (`tests/pipeline/test_init.sh`)
- AC-43 (FR-1): A fresh `init.sh` install has an executable `scripts/pipeline/install-merge.sh` identical to `REPO_SRC`, and `.install-manifest` lists it. A re-run with it hand-edited reports it as `customised, kept`.
- AC-44 (FR-11): In `commands/pipeline-init.md`, question 7 still lists exactly four options, and the Branches option contains `merge the install pull request` and `no human review`.
- AC-45 (FR-12): In `commands/pipeline-init.md`, the first line naming `install-merge.sh` comes before the first line naming `host.sh protect`, and the doctor step comes before both.
- AC-46 (FR-10, FR-16): `commands/pipeline-init.md` names `install-merge.sh --open-only` as the fallback, names the `REFUSED` outcome, and states that init never uses an admin merge, never changes protection and never adds the infra label. It contains no `gh pr merge`, `glab mr merge` or `--admin` command.
- AC-47 (FR-11): `commands/pipeline-init.md` keeps today's step-8 instruction for when "Branches" is unticked: push a branch, open a request for the owner to mark `infra` and merge, or let the owner push it.
- AC-48 (FR-14): Both copies of `BRANCHING.md` ("Repository maintenance without a ticket") and the README name `install-merge.sh`, say `without a human review`, and describe the owner fallback.
- AC-49 (FR-14, R8): No file in `README.md`, `CHANGELOG.md`, `docs/pipeline/*.md`, `template/docs/pipeline/*.md` or `commands/pipeline-init.md` describes the install merge as reviewed. Checked by a grep over the new text for `reviewed install` and `install is reviewed`.
- AC-50 (FR-14): `.claude-plugin/plugin.json` version is `3.2.0`. `CHANGELOG.md` opens with a `## v3.2.0` section that describes the route, the guard change, the fallback and the SHI-46 limit (protected-trunk upgrades still fall back).
- AC-51 (FR-15): The persona project-agnosticism test still passes, and `agents/*.md` and `.claude/agents/*.md` are identical pairs.
- AC-52 (Metric 1, manual, for QA): Given a throwaway GitHub repo with no protection, when `/pipeline-init` is run from the qa ref with every consent ticked, then the owner's only action after the sign-in is none, `git log origin/master` contains the install, protection is applied afterwards, and the Impact line reads `Install merged into …`.

## Interpretations (BA decisions derived from product.md; none loosens R1–R8)
1. R1c says "every file is one init.sh installs or scaffolds; tooling identical". R1c's own example lists a hand-edited `.claude/settings.json` hook entry as a hole. So the safety-bearing project files are held to identity as well: settings.json, CI files, deploy scripts and `.new` copies (class S). This is stricter. It costs nothing on the default path, because a fresh install creates them from the template and a re-run does not touch them.
2. `.gitlab-ci.yml` is accepted only in the two forms `init.sh` itself produces. An agent-edited `include:` list (the `ACTION:` case) and a merge into an existing `bitbucket-pipelines.yml` fall back to the owner.
3. R6 says "byte-for-byte". R7 explicitly changes the guard's block message. So every existing decision (exit code) is identical, and the only text change is the added "Ways forward" line.
4. The trusted reference (FR-4) follows the hook's existing trust model: the hook's own environment, like `PIPELINE_BYPASS`, and Claude Code's records, never the command.

## Delivery notes
- Flags / env: no new `pipeline.env` key. Only the existing test doubles are used. The reference lookup (FR-4) is the engineer's to implement within its constraints. Preferred approach: the verifier comes from the reference itself (for example an `init.sh --list`/render mode, or a verifier shipped in the plugin), so the install set is defined in one place.
- Rollout order: SHI-47, then SHI-48 and SHI-49 in parallel, then SHI-50. Existing installs get the route and the new guard on their next `/pipeline-init` re-run.
- Known limits, stated in the docs and CHANGELOG:
  - The guard sees agent tool calls only. A script that calls the host API internally is not examined (unchanged).
  - The owner's consent (R5) is enforced by `/pipeline-init`'s instructions, not by the guard.
  - The install request's Pipeline Gate check shows as failed. That is expected until SHI-46.
  - The reference is only as trustworthy as the user's plugin install.
- CONTEXT.md "stop and ask before altering the write-boundary hooks": the owner approved this change in product.md.
