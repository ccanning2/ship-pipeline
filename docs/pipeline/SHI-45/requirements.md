# SHI-45 — Requirements (engineer-ready)

Status: approved
Traces to: product.md (US-1..US-6, R1..R8)
Amended: 2026-09-28 for defect SHI-55 (owner decision: the route checks against the real trunk; the guard stays
network-free). Amended items are marked "(amended, SHI-55)"; FR-17, FR-18 and AC-53..AC-63 are new.

`/pipeline-init` opens the install pull request and merges it into the trunk itself. It does this through one
dedicated route, `scripts/pipeline/install-merge.sh`. The guard hook (`scripts/pipeline/hooks/guard-merge.sh`) lets that
route through only when the route is the plugin's own copy, runs alone, and passes a local pre-check. The route then
proves, against the trunk as the host reports it, that the request is nothing but the pipeline's own install, before
it pushes and again before it merges. Every other agent push or merge is decided exactly as today.

Terms used below:
- **trust boundary** (new, SHI-55): *project state* is everything inside the project repository. That means the
  working tree, the index, committed files, `.git` configuration (remotes, their URLs, URL rewrites, hooks), every
  ref, and the words of the command. An agent can set all of it, so none of it is ever proof on its own. *Trusted
  inputs* are the hook's own environment and Claude Code's records (FR-4), the installed plugin, and the host itself,
  as read through the owner's signed-in CLI or API token. The proof may rest only on trusted inputs, plus project
  content checked against them.
- **trunk**: `BASE_BRANCH`; **staging branch**: `STAGING_BRANCH`; **remote**: `PIPELINE_REMOTE` (default `origin`).
  The route reads these keys from the working-tree `pipeline.env` as literal values (FR-18), and they must equal the
  committed ones (FR-3.2). The remote only says which repository git fetches from and pushes to. It is never
  evidence of what the trunk contains. (amended, SHI-55)
- **host repository** (new): the repository `host.sh` addresses. Its host comes from `GIT_HOST` / `GIT_HOST_URL`, and
  its path comes from the remote's URL. The request is opened, read and merged there.
- **install branch**: the reserved branch name `ship-pipeline/install`. It has no digits, so it never matches a
  ticket id. It is not `infra/*`, so it never means "infra" on Bitbucket. It is a label only, never the proof.
- **install commit**: `HEAD` when the route runs.
- **trunk tip (T)** (amended, SHI-55): the commit sha the host reports, while the route runs, as the head of the trunk
  in the host repository (FR-17). No local ref is the trunk tip: not `refs/remotes/<remote>/<trunk>`, not
  `refs/heads/<trunk>`, not `FETCH_HEAD`, not a tag. The commit is identified by its sha alone. A local copy of it is
  used only as the object whose id is T.
- **local trunk ref** (new): `refs/remotes/<remote>/<trunk>`. Only two things use it: the guard's network-free
  pre-check (FR-5d) and `/pipeline-init` when it creates the install branch (FR-12). Any agent can set it, so it is
  never proof.
- **real history** (new): ancestry and diffs as git's own objects give them. Replace refs and grafts are ignored. If
  a shallow boundary hides the answer, the commit counts as "not an ancestor".
- **install diff** (amended): `git diff --no-renames T <install commit>`, as added / modified / deleted paths plus
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
  - `install-merge.sh`: verify, push, open or reuse the request, verify again, merge.
  - `install-merge.sh --open-only`: push and open or reuse the request, never merge.
  Any other argument is a usage error (exit 1) and does nothing. `scripts/init.sh` classifies it as **tooling**:
  it is installed, recorded in `.install-manifest` and made executable, and it is listed in the header comment's
  tooling list.
- FR-2 (R1b, R1d): The route requires the current local branch to be the install branch. It pushes `HEAD` to
  `refs/heads/ship-pipeline/install` on the remote, never with force. It targets the trunk only. It never pushes,
  moves or deletes the staging branch, a tag, or any ref other than the install branch.
- FR-3 (R1c): **The proof.** A request is init's install only if every one of these checks passes on the install
  commit (the blob contents at that commit, not the working tree):
  1. (amended, SHI-55) T exists as a commit, is an ancestor of the install commit in real history, and the install
     diff is not empty. In the route, T is the host's trunk tip (FR-17). In the guard's pre-check only, the local
     trunk ref stands in for T (FR-5d).
  2. (amended, SHI-55) `BASE_BRANCH`, `GIT_HOST`, `GIT_HOST_URL` and `PIPELINE_REMOTE` in the committed `pipeline.env`
     equal the same keys in the working-tree `pipeline.env`, compared after defaults (`PIPELINE_REMOTE` defaults to
     `origin`, `GIT_HOST_URL` to empty). So the route acts only with the configuration it is merging.
  3. Every added or modified path belongs to the **install set** for the declared configuration, and its content
     meets its class:

     | Class | Paths (only those `init.sh` installs for the declared configuration) | Content rule |
     |---|---|---|
     | T: tooling | every tooling destination in `init.sh`. Includes `scripts/pipeline/*.sh` in its tooling loop (with `install-merge.sh`), `host.sh` (= `adapters/host-<GIT_HOST>.sh`), `tracker.sh` (= `adapters/tracker-<TRACKER>.sh`), `lib/host-common.sh`, `lib/tracker-common.sh` (not for connector), `tracker-schema.txt`, `hooks/*.sh`, `.claude/agents/<each agents/*.md>`, `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md`, `docs/pipeline/_templates/<each template>` | identical to the reference copy, rendered |
     | S: safety-bearing project files | `.claude/settings.json`; the host's CI files (`.github/workflows/pipeline-gate.yml`, `deploy.yml` when deploy envs are on; `.gitlab/pipeline-gate.yml`, `.gitlab/pipeline-deploy.yml`; `bitbucket-pipelines.yml` or `bitbucket-pipelines.ship.yml` from the matching template); `scripts/deploy/{deploy,rollback,smoke}.sh` when deploy envs are on; any `<T or S path>.new` | identical to the reference template or file, rendered. A `.new` file matches the reference copy of the file it sits beside |
     | G: `.gitlab-ci.yml` (GitLab only) | `.gitlab-ci.yml` | either a new file that is exactly what `init.sh` generates when none exists, or T's version followed by exactly the `# ship-pipeline` include block `init.sh` appends. Any other change, including an edit to an existing `include:` list, fails |
     | F: free project files | `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md`, `docs/pipeline/README.md`, `scripts/pipeline/pipeline.env`, `scripts/pipeline/tracker.map`, `.gitignore`, `scripts/pipeline/.install-manifest` | any content (see follow-up NEW-1 for `pipeline.env`) |

  4. Every deleted path is one `init.sh` retires. That means a path under `scripts/pipeline/`, `.claude/agents/`,
     `docs/pipeline/_templates/`, `docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md` or `tests/pipeline/` that is **not** in
     the current install set and is recorded in T's `.install-manifest`, or a stale `.new`, or `.gitignore.pipeline`.
     Any other deletion fails.
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
  - c. the files the route relies on are identical to the reference in the working tree. They are
    `install-merge.sh`, `host.sh`, `lib/host-common.sh`, `base-ref.sh`, `ticket-id.sh`, `hooks/guard-merge.sh` itself,
    and any other project file the route runs after the SHI-55 fix;
  - d. (amended, SHI-55) the merge form only: the current branch is the install branch, and FR-3 passes against the
    local trunk ref. This is a network-free **pre-check** (NFR-2). It catches honest mistakes early. It is not the
    proof: the route's host-anchored check (FR-17) decides the merge;
  - e. (new, SHI-55; was an engineering decision, now required because the proof relies on it) the route is the whole
    command. No other command, variable assignment or pipe may appear in the same call. A trailing `2>&1` is fine.

  When any check fails, the guard blocks (exit 2) and names the first failing check and path (copy below). It never
  asks for a ticket for this command.
- FR-6 (R1a, R6): Every existing route stays gated exactly as today, including from the install branch:
  - `git push` / `git merge` into the trunk or staging;
  - `gh pr merge`, `glab mr merge`;
  - API merges and ref and tag writes;
  - `host.sh merge|set-ref|request-merge`;
  - force pushes, deletes and bulk pushes;
  - the `infra` label and Bitbucket `infra/` branches;
  - version tags.

  The install branch name, a marker file, `PIPELINE_TICKET` and any flag grant nothing outside FR-5. `PIPELINE_BYPASS=1`
  in Claude Code's own environment still lets any command through, including the route, and the bypass is announced.
  Any read-only `host.sh` verb added for FR-17 is decided like the existing read verbs. It is not a merge or a ref write.
- FR-7 (US-1, R4) (amended, SHI-55): **Route, merge form.** Before anything else the route runs the FR-17 check
  (steps 1–3). This is defence in depth, and it is the whole check when the route is run from the owner's terminal.
  Then it:
  1. pushes the install branch (FR-2);
  2. reuses an open request from the install branch into the trunk, or opens one. Title: `chore: install ship pipeline`
     on a first install, `chore: update ship pipeline to v<reference version>` when T already has
     `scripts/pipeline/.install-manifest`. Body: FR-14 copy;
  3. waits, bounded by `PIPELINE_WAIT_TRIES`, while the host is still working out whether the request can be merged;
  4. runs the FR-17 pre-merge check (step 4);
  5. merges the request **at the install commit's sha**. GitHub and GitLab pass the sha to the merge call. On Bitbucket
     the source commit is re-read in step 4, right before merging. All three hosts go through `host.sh`, so every
     adapter (github, gitlab, bitbucket) is covered.

  It never re-sends a merge the host refused.
- FR-8 (US-1, US-6): After a successful merge the route:
  - fetches the trunk, switches the working tree to the trunk and fast-forwards it to the remote trunk;
  - deletes the install branch on the remote and locally (US-6, Could). If the deletion fails, that is a `NOTE`,
    not a failure.
- FR-9 (R2, US-3): **Host refusal.** Any refusal by the host ends the route with exit 3 and one line:
  `REFUSED <request url> <reason>`. Refusals include:
  - a required review, a required check, rulesets or missing permission;
  - a rejected push;
  - a source-commit mismatch;
  - an API that Bitbucket Data Center lacks;
  - (amended, SHI-55) any failure of the FR-17 host reads: an unreachable network or host, the owner not signed in,
    no such branch, a trunk that moved, or a request that targets another branch.

  The route never:
  - uses an admin or bypass merge;
  - reads or changes branch protection or rulesets;
  - adds, removes or requests any label;
  - retries through another route;
  - force-pushes.

  If no request could be opened, `<request url>` is the host's web URL for the repository.
- FR-10 (R2, US-3) (amended, SHI-55): **Route, open-only form.** `--open-only` pushes the install branch and opens or
  reuses the request, exactly as FR-7 steps 1–2. It prints `OPENED <url>` and never merges. It does not read T,
  because it never merges. `/pipeline-init` uses it as the fallback when the guard or the route refuses the merge
  form. If `--open-only` is also refused (for example the network is down), `/pipeline-init` reports the "not opened"
  fallback line (copy below). The install stays committed on the local install branch.
- FR-11 (R5, US-4): Call 2, question 7 still has four options. "Branches" becomes: create the branches, merge the
  install request without a human review, then protect both (copy below). With "Branches" unticked, step 8 is
  today's text and flow, unchanged, and the route is not run.
- FR-12 (R3): With "Branches" ticked, `/pipeline-init` runs, in this order:
  1. doctor;
  2. fetch the trunk, then create the local install branch from the freshly fetched local trunk ref, and commit only
     the install's files on it. Those are the files `init.sh` reported, CONTEXT.md, RELEASE_CHECKLIST.md,
     `tracker.map`, and any `ACTION:` CI merge. The route re-checks against the host (FR-17), so this ref is only a
     starting point;
  3. run the route;
  4. only then `host.sh protect <trunk>` and `protect <staging>`, as today, whatever the merge outcome;
  5. `enforcement.sh`.
  The Pipeline Gate's pass/fail conditions (`ci-gate.sh`, `pipeline-gate.yml`, `gate.sh`) do not change.
- FR-13 (US-5): A re-run (upgrade) follows the same flow and route. Where the host already requires the gate or a
  review, FR-9 applies.
- FR-14 (R7, R8): The docs say that init merges its own install request **without a human review**. They say it falls
  back to the owner when the host or the guard refuses, and that a team that wants a review leaves "Branches" unticked
  or keeps a required review on the trunk. (amended, SHI-55) They also say, in one sentence each in `BRANCHING.md` (both
  copies) and the CHANGELOG `v3.2.0` section, that the route checks the install against the trunk as the host reports
  it, before the push and again before the merge, and falls back to the owner when the host cannot be reached. The docs
  covered are:
  - `docs/pipeline/BRANCHING.md` and `template/docs/pipeline/BRANCHING.md` ("Repository maintenance without a ticket");
  - `commands/pipeline-init.md` step 8;
  - README (the "Work without a ticket" paragraph and the hooks line);
  - CHANGELOG (new `v3.2.0` section);
  - the guard's block message.
  No doc says the install is reviewed. `.claude-plugin/plugin.json` version is `3.2.0`. It has not been released yet,
  so no further bump.
- FR-15 (R6): `/ship` never uses the route. `commands/ship.md`, `agents/*.md` and `.claude/agents/*.md` do not name
  `install-merge`.
- FR-16 (US-3): The final reply of `/pipeline-init` reports the merge outcome under **Impact**. That is
  `Install merged into <trunk>: <url>`, or one of the two fallback lines (copy below), along with the doctor result and
  the enforcement mode as today.
- FR-17 (new, SHI-55; R1, R2, R4): **Host-anchored proof (route, merge form).** On every host (github, gitlab,
  bitbucket), through `host.sh`:
  1. *Read T before the push.* The route asks the host for the head sha of the trunk in the host repository. It makes
     one attempt, with no retry loop. If the answer cannot be had, the route exits 3 with
     `REFUSED <web url> the trunk tip could not be read from the host (<reason>)`, before any push or request call.
     This covers a network or host that cannot be reached, the owner not signed in, no such branch, and an answer that
     is not a full commit sha.
  2. *Obtain commit T.* If no commit with id T exists locally, the route fetches the trunk from the remote and looks
     again, by id only. It never takes whatever a ref points at. If there is still no commit T, the route exits 3 with
     `REFUSED <web url> the host's trunk tip <T> could not be fetched`, before any push.
  3. *Prove.* The route runs the FR-3 proof with this T, through the reference's own verifier (the one definition of the
     install set). The verifier reads ancestry and diffs in real history. A failure exits 4 with
     `NOT-INSTALL <path>: <reason>`, before any push or request call. The FR-7 title, FR-3.4 retired files, FR-3 G and
     NFR-4 "nothing to merge" all use this T.
  4. *Re-check before the merge.* After the FR-7 wait and right before the merge call, the route reads the request
     from the host again, and the trunk's head from the host again. All three of these must hold:
     - the request's source commit is the install commit (as today);
     - the request's target branch is the trunk;
     - the host's trunk head is still T.
     Any mismatch or failed read exits 3 with one `REFUSED <request url> <reason>` line and makes no merge call.
     Re-running the route starts again from step 1.
  5. The route never uses the local trunk ref, `FETCH_HEAD` or any other ref as T or as evidence for T.
     `PIPELINE_REMOTE` and the remote's URL settings can change where git fetches from and pushes to. They cannot
     change the T that the proof and the re-check use, because both come from the host repository where the merge
     happens.
- FR-18 (new, SHI-55; R1): **pipeline.env is read, not run, by the route.** This applies to `install-merge.sh`, to the
  verifier it runs, and to every `host.sh` / `base-ref.sh` call the route makes. In all of them the project's
  `pipeline.env` is never executed. Only these keys are taken from it: `GIT_HOST`, `GIT_HOST_URL`, `TRACKER`,
  `BASE_BRANCH`, `STAGING_BRANCH`, `PIPELINE_REMOTE`, `DEPLOY_MODE`, `PIPELINE_HAS_DEPLOY_ENVS`. They are read as
  literal values with `init.sh`'s existing parsing rules. No other line has any effect on the route, including a
  command, a function, an `export`, or any other assignment. The test doubles `PIPELINE_GH_CMD`, `PIPELINE_GLAB_CMD`,
  `PIPELINE_CURL_CMD` and `PIPELINE_WAIT_TRIES` count only when they come from the process environment. Host
  credentials come from where they come from today (the CLIs' own sign-in, the environment,
  `~/.config/ship-pipeline/bitbucket.env`). Every other script, and the guard for every other command, reads
  `pipeline.env` as today (follow-up NEW-1).

## Non-functional requirements
- NFR-1 (safety, high-risk area): Fail closed. Any error, missing tool, missing ref or commit, unreadable blob, host
  read that failed or was ambiguous, or unreachable network, during the FR-3 / FR-5 / FR-17 checks blocks the route.
  It never allows it. Refused runs change nothing on the host except what was already done (at most the pushed
  install branch and an open request).
- NFR-2 (performance and network) (amended, SHI-55):
  - *Guard.* The guard never uses the network, for any command, including the route. Its cost for every command other
    than `install-merge.sh` stays as today: no extra process per call beyond today's. Its route pre-check (FR-5d)
    stays local and finishes within a few seconds on Windows Git Bash for a full install diff (~70 files).
  - *Route.* The merge form uses the network for these calls only:
    - one host read of T and, only when commit T is missing locally, one fetch of the trunk (FR-17.1–2);
    - the push and the request calls, as today;
    - the bounded wait;
    - one re-read of the request and of the trunk head before the merge (FR-17.4).
    The local part of its proof has the same bound as the guard's pre-check. Checksums stay batched the way
    `init.sh` does them. The open-only form makes no call that it did not make before this amendment.
- NFR-3 (portability): bash 3.2 (macOS), Git Bash on Windows, GNU and BSD tools, CRLF checkouts. No new runtime
  dependency. `jq` stays optional in the guard, as today.
- NFR-4 (idempotency): Re-running the route after a successful merge makes no change and exits 1 with "nothing to
  merge". Re-running it with an open request reuses that request. A run refused by FR-17 can be re-run as-is once the
  cause is gone.
- NFR-5 (no secrets): The route prints URLs, shas and reasons only, never tokens or API payloads.
- NFR-6 (tests): Fixtures only, under `mktemp -d`. The "remote" is a local bare repository. The host is the existing
  test doubles (`PIPELINE_GH_CMD`, `PIPELINE_GLAB_CMD`, `PIPELINE_CURL_CMD`), passed in the process environment and
  extended to answer the FR-17 reads from the bare repository. No network.

## Data model changes
| Entity/table | Change | Constraints/indexes | Migration notes |
|---|---|---|---|
| (files) `scripts/pipeline/install-merge.sh` | new tooling file | executable; in `.install-manifest` | installed on the next `/pipeline-init` re-run; not destructive |
| (git) branch `ship-pipeline/install` | reserved name | never force-pushed; deleted after merge | none |
| (host verbs) read of a branch head, and the request's target branch, if the engineer adds them (SHI-55) | new read-only `host.sh` output | all three adapters; no write, label, protection or admin call | none |

## CLI contract
| Command | Who | Request | Output / exit | Errors | Breaking? |
|---|---|---|---|---|---|
| `bash scripts/pipeline/install-merge.sh` | `/pipeline-init` only (agent, through the guard), or the owner's terminal | no args; current branch = install branch | `MERGED <url>` then optional `NOTE <text>` lines; exit 0 | 1 usage / nothing to merge / no remote; 3 `REFUSED <url> <reason>` (host refusal, or a FR-17 host read failed or disagreed); 4 `NOT-INSTALL <path>: <reason>` (proof against T, before any push) | no (new) |
| `bash scripts/pipeline/install-merge.sh --open-only` | `/pipeline-init` fallback | as above | `OPENED <url>`; exit 0 | 1; 3 `REFUSED <url> <reason>` | no |
| guard, route segment | hook | the Bash tool call | exit 0 allow; exit 2 block with message; never a network call | n/a | no |
| guard, every other segment | hook | as today | unchanged decisions | unchanged | no |

## UI changes (owner-facing copy)
| Where | Change | States | Copy |
|---|---|---|---|
| `/pipeline-init` Call 2 q7, "Branches" | wording | ticked by default | **Branches:** create the trunk and staging branches if the remote lacks them, merge the install pull request (no human review), then protect both so the Pipeline Gate is required. |
| `/pipeline-init` Impact, merged | new line | success | `Install merged into <trunk>: <url>` |
| `/pipeline-init` Impact, fallback | new line | host or guard refused | `Install pull request not merged (<reason>). Open <url>, mark it infra and merge it (on Bitbucket, push the branch as infra/<name>).` |
| `/pipeline-init` Impact, not opened (new, SHI-55) | new line | `--open-only` also refused (e.g. network or host down) | `Install pull request not opened (<reason>). The install is committed on the local branch <install branch>: push it, open a request into <trunk>, mark it infra and merge it (on Bitbucket, push the branch as infra/<name>).` |
| guard block, route refused | new message | block | `PIPELINE GATE: blocked '<segment>' (install route): <reason>. This route merges only the pipeline's own install: every changed file must be one that scripts/init.sh installs, and each tooling file must match the plugin's copy. Way forward: run 'bash scripts/pipeline/install-merge.sh --open-only' and leave the request for the owner to mark infra and merge. Do not try to get around this hook.` |
| guard block and `NOT-INSTALL`, reasons (`<reason>`) | new | block | `<path> is not part of the install` · `<path> differs from the plugin's copy` · `<path> is deleted but is not retired tooling` · `the current branch is '<b>', not 'ship-pipeline/install'` · `<remote>/<trunk> is missing or not an ancestor of HEAD` (guard pre-check) · `the host's <trunk> (<T>) is not an ancestor of HEAD` (route) · `nothing to merge` · `the plugin's installed copy could not be found` · `the route must be run as scripts/pipeline/install-merge.sh` · `unexpected argument '<a>'` · `<file> (used by the route) differs from the plugin's copy` · `the route must run on its own: no variable assignment and no other command in the same call` · `scripts/pipeline/pipeline.env at HEAD says <KEY>="<v>", but the working tree says "<w>"` |
| route `REFUSED` reasons (new, SHI-55) | new | exit 3 | `the trunk tip could not be read from the host (<reason>)` · `the host's trunk tip <T> could not be fetched` · `the trunk moved since the check (host: <sha>, checked: <T>)` · `the request targets '<b>', not '<trunk>'` · `the request could not be read (<reason>)` |
| guard `no_ticket` message | one line added under "Ways forward" | block | `  - The pipeline's own install or upgrade: /pipeline-init merges it through scripts/pipeline/install-merge.sh, which accepts nothing but the plugin's own files.` |
| PR/MR body | new | on open | `Ship pipeline install, opened and merged by /pipeline-init without a human review. Every file matches the plugin's copy or is a project file init.sh scaffolds (docs/pipeline/BRANCHING.md).` |

## Permissions matrix
| Action | Agent via `install-merge.sh` | Agent via any other route | `/ship` / personas | Owner's own terminal | `PIPELINE_BYPASS=1` (Claude Code env) |
|---|---|---|---|---|---|
| Ticketless merge of a verified install (against the host's trunk) into the trunk | allowed | blocked (as today) | never used | allowed (the route's own FR-17 check still runs) | allowed, announced |
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
- AC-16 (FR-3.1, FR-5d, FR-17) (amended, SHI-55): Guard pre-check: given the local `origin/master` missing, or not an ancestor of HEAD, then blocked. Given HEAD equal to it, then blocked: `nothing to merge`. Route, run directly with the fake host: given the host's trunk head is not an ancestor of HEAD, then exit 4 `NOT-INSTALL: the host's master (<T>) is not an ancestor of HEAD`. Given it equals HEAD, or HEAD is its ancestor, then exit 1 `nothing to merge`. Either way there is no push and no request call.
- AC-17 (FR-3.2) (amended, SHI-55): Given the committed `pipeline.env` saying `BASE_BRANCH="main"` while the working tree says `master`, then blocked. The same holds, one case each, for `GIT_HOST`, `GIT_HOST_URL` and `PIPELINE_REMOTE` differing between the committed and working-tree `pipeline.env`, in the guard and in the route run directly (exit 4).
- AC-18 (FR-5d): Given the AC-1 install committed on `chore/install` (not the install branch), then blocked.
- AC-19 (FR-5a): Given a copy of the route at `/tmp/x/install-merge.sh` or `scripts/other/install-merge.sh`, when that path is run, then blocked: `the route must be run as scripts/pipeline/install-merge.sh`.
- AC-20 (FR-5b): Given `install-merge.sh --force`, `install-merge.sh master`, or `install-merge.sh --open-only x`, then blocked: `unexpected argument`.
- AC-21 (FR-5c): Given the working-tree `install-merge.sh` or `lib/host-common.sh` edited, when either form runs, then blocked.
- AC-22 (FR-4): Given no reference reachable from the hook's environment, when the route runs, then blocked: `the plugin's installed copy could not be found`.
- AC-23 (FR-4): Given an edited `guard-merge.sh` in the install commit, and a reference location or fake plugin root given in the command (an argument, `VAR=… bash scripts/pipeline/install-merge.sh`, or a file under the project such as `.claude/.pipeline-init`), then the guard still compares against the true reference and blocks.

Guard, negative: R6 (unchanged guarantees)
- AC-24 (FR-6): Given the change, when `bash tests/pipeline/run-all.sh` runs, then every existing case in `test_guard_merge.sh` and in the guard section of `test_adapters.sh` passes with its existing expected exit code. `git diff d7815e3 -- tests/pipeline/test_guard_merge.sh tests/pipeline/test_adapters.sh` shows only added lines.
- AC-25 (FR-6): Given the current branch is `ship-pipeline/install` with a valid install commit and no ticket, then each of these is blocked (exit 2) and names `no ticket id`: `git push origin HEAD:master`; `gh pr merge 5 --merge`; `gh api -X PUT repos/o/r/pulls/5/merge`; `glab mr merge 5`; `bash scripts/pipeline/host.sh merge ship-pipeline/install master x`; `bash scripts/pipeline/host.sh request-merge 5 <sha>`. A bare `git push` there pushes the install branch itself, so it stays allowed, as today (R6).
- AC-26 (FR-6): Given the install branch, then `git push origin HEAD:staging`, `git push origin v1.0.0`, `git push --force origin HEAD:master`, `git push --all origin`, `gh pr edit 5 --add-label infra` and, on bitbucket, `git push origin HEAD:infra/x` are blocked as today.
- AC-27 (FR-5e, FR-6): Given `bash scripts/pipeline/install-merge.sh && git push origin HEAD:master` on a valid install, then the command is blocked (the push segment is blocked as a push; the route does not run alone).
- AC-28 (FR-6): Given `PIPELINE_BYPASS=1` in the hook's environment and an invalid install, when the route runs, then it is allowed and the bypass is announced. Given `PIPELINE_BYPASS=1` written into the command, then it is still blocked.
- AC-29 (FR-6, FR-14): Given a ticketless `git push` on master, then the block message still contains `'infra' label`, `own terminal` and `Do not try to get around`, and now also `install-merge.sh`.
- AC-30 (FR-15): `commands/ship.md`, `agents/*.md` and `.claude/agents/*.md` do not contain `install-merge`.

Route (in `tests/pipeline/test_install_merge.sh`. The remote is a local bare repo. The `PIPELINE_GH_CMD` / `PIPELINE_GLAB_CMD` / `PIPELINE_CURL_CMD` fakes are passed in the process environment, log every call, and report the trunk head from the bare repo unless a case says otherwise. `PIPELINE_WAIT_TRIES=1`)
- AC-31 (FR-7, FR-17) (amended, SHI-55): Given a GitHub fixture with a valid install on the install branch, when `install-merge.sh` runs, then it:
  - reads the trunk head from the host before any push;
  - pushes `ship-pipeline/install` without force;
  - opens a request with head `ship-pipeline/install`, base `master` and title `chore: install ship pipeline`;
  - re-reads the request and the trunk head after the wait and before the merge;
  - merges with `sha=<install commit>`;
  - prints `MERGED <url>` and exits 0.
- AC-32 (FR-7, FR-17) (amended, SHI-55): The same for GitLab (MR merge with `sha`) and Bitbucket (source commit, target branch and trunk head re-read, then the merge is called).
- AC-33 (FR-7): Given an open request from the install branch already exists, then it is reused and none is created.
- AC-34 (FR-7, FR-17) (amended, SHI-55): Given T (the host's trunk head) already contains `.install-manifest`, then the title is `chore: update ship pipeline to v<reference version>`. This holds even when the local `origin/master` is missing.
- AC-35 (FR-9): Given the fake host rejects the merge (GitHub 405 "required status check", GitLab 405/406, Bitbucket 400/403), then the route:
  - exits 3 with exactly one `REFUSED <url> <reason>` line;
  - makes no second merge call;
  - makes no call containing `protection`, `rulesets`, `protected_branches`, `branch-restrictions`, `labels`, `--admin` or `bypass`.
- AC-36 (FR-9): Given Bitbucket reports a source commit other than the install commit, then there is no merge call and the route exits 3.
- AC-37 (FR-9, FR-2): Given the remote rejects the push of the install branch, then the route exits 3, never retries with force, and makes no merge call.
- AC-38 (FR-7, FR-3) (amended, SHI-55): Given the install commit adds `src/app.js`, when the route is run directly (without the hook), then it exits 4 `NOT-INSTALL src/app.js: …`. The only host call before that is the trunk-head read: there is no push and no request call.
- AC-39 (FR-8): Given a successful merge, then:
  - the working tree is on `master` at the remote trunk;
  - the install branch is deleted on the remote and locally;
  - a failed delete gives a `NOTE` line and still exit 0.
- AC-40 (FR-10): Given `--open-only`, then the route pushes and opens or reuses the request, prints `OPENED <url>`, exits 0, and makes no merge call and no trunk-head read.
- AC-41 (FR-2, FR-1): The route's host call log never names the staging branch, a `refs/tags/` ref or a force flag, and any argument other than `--open-only` exits 1 with no calls.
- AC-42 (NFR-4) (amended, SHI-55): Given a second run after AC-31, then exit 1 with `nothing to merge`, with no push and no request call.

Route, host-anchored proof (new, SHI-55; each on the GitHub, GitLab and Bitbucket fakes unless stated)
- AC-53 (FR-17, R1; SHI-55 repro, GitHub): Given a bare `origin` whose `master` is commit A, and a branch `evil` from A that adds `src/Backdoor.java`. The install branch holds the `init.sh` output committed on top of `evil`. `git update-ref refs/remotes/origin/master evil` has been run. When the route runs (directly, and through the guard with the reference = the fixture plugin), then it exits 4 `NOT-INSTALL src/Backdoor.java: src/Backdoor.java is not part of the install`. The fake host log shows only the trunk-head read. The bare origin has no `ship-pipeline/install` branch, and no request is opened or merged. (The guard's local pre-check may allow this command. What must hold is the outcome.)
- AC-54 (FR-17, R4): Given the AC-53 fixture on the GitLab and on the Bitbucket fakes, then the same outcome.
- AC-55 (FR-17, FR-18; SHI-55 second spelling): Given `PIPELINE_REMOTE="fork"` in both the working-tree and the committed `pipeline.env` (so FR-3.2 passes). `fork` is a second local bare repo whose `master` is `evil`. `refs/remotes/fork/master` is `evil`. The host reports the trunk head as A. When the route runs, then it exits 4 `NOT-INSTALL src/Backdoor.java: …` with no push and no request call, on all three fakes.
- AC-56 (FR-17.4): Given a valid install where the host reports a trunk head other than T at the pre-merge re-read (the trunk moved, or the head comes from a different repository), then the route exits 3 `REFUSED <url> the trunk moved since the check (host: <sha>, checked: <T>)` and makes no merge call.
- AC-57 (FR-17.4): Given a reused open request from the install branch whose target branch, as the host reports it, is `staging` (or any branch other than the trunk), then the route exits 3 `REFUSED <url> the request targets 'staging', not 'master'` and makes no merge call.
- AC-58 (FR-17.1–2, NFR-1): Given the trunk-head read fails (the fake CLI exits non-zero, `curl` fails as if the network were down, the branch is unknown, or the answer is not a full sha), then the route exits 3 `REFUSED <web url> the trunk tip could not be read from the host (<reason>)`, before any push or request call. Given the host reports a sha that the remote does not have, then the route exits 3 `REFUSED <web url> the host's trunk tip <sha> could not be fetched`, before any push.
- AC-59 (FR-18): Given the working-tree and committed `pipeline.env` also hold a line setting `PIPELINE_GH_CMD` (on GitLab `PIPELINE_GLAB_CMD`, on Bitbucket `PIPELINE_CURL_CMD`) to a liar fake that reports `evil` as the trunk head, and a line `touch <marker>`. The process environment holds the honest fake. When the route runs directly on the AC-53 fixture, then:
  - only the honest fake is called;
  - the route exits 4 naming `src/Backdoor.java`;
  - `<marker>` does not exist afterwards.
- AC-60 (FR-17.3, real history): Given an install commit whose real history does not contain T, but a replace ref, or a `.git/info/grafts` entry, makes T look like an ancestor, then the route exits 4 (T is not an ancestor of HEAD) with no push. Given a shallow repo where the ancestry cannot be decided, then the route refuses with exit 3 or 4, with no push. GitHub fake only.
- AC-61 (FR-17.5, positive): Given a valid install built on A, with the host reporting A, and the local `origin/master` deleted, or pointing at an older trunk commit, then the route run directly merges (`MERGED <url>`, exit 0). The proof does not depend on the local ref.

Guard, network (new, SHI-55; in `test_guard_merge.sh`, added lines only)
- AC-62 (NFR-2): Given `PIPELINE_GH_CMD`, `PIPELINE_GLAB_CMD` and `PIPELINE_CURL_CMD` in the hook's environment pointing at a fake that logs and fails, and the remote's URL pointing at a path that does not exist, when the guard runs the AC-1, AC-8 and AC-53 route cases and one ordinary ticketless push, then its decisions are the same as without them and the fake log is empty.

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
- AC-63 (FR-10, FR-14, FR-16; new, SHI-55): `commands/pipeline-init.md` contains the "not opened" Impact line and says to report it when `--open-only` is also refused. Both `BRANCHING.md` copies and the `v3.2.0` CHANGELOG section say that the route checks the install against the trunk as the host reports it, before the push and before the merge, and falls back to the owner when the host cannot be reached.

## Interpretations (BA decisions derived from product.md; none loosens R1–R8)
1. R1c says "every file is one init.sh installs or scaffolds; tooling identical". R1c's own example lists a hand-edited `.claude/settings.json` hook entry as a hole. So the safety-bearing project files are held to identity as well: settings.json, CI files, deploy scripts and `.new` copies (class S). This is stricter. It costs nothing on the default path, because a fresh install creates them from the template and a re-run does not touch them.
2. `.gitlab-ci.yml` is accepted only in the two forms `init.sh` itself produces. An agent-edited `include:` list (the `ACTION:` case) and a merge into an existing `bitbucket-pipelines.yml` fall back to the owner.
3. R6 says "byte-for-byte". R7 explicitly changes the guard's block message. So every existing decision (exit code) is identical, and the only text change is the added "Ways forward" line.
4. The trusted reference (FR-4) follows the hook's existing trust model: the hook's own environment, like `PIPELINE_BYPASS`, and Claude Code's records, never the command.
5. (SHI-55) **Where the trusted trunk comes from.** No remote name, remote URL or ref inside the project can be trusted: the remote list is `.git/config`, and any agent can write refs. So the proof does not try to pick a "trusted remote". It anchors to the one repository that matters, the host repository where the merge happens, and reads T there. The pre-merge re-check (FR-17.4) is sufficient on its own terms. If all of these hold:
   - the host's trunk head is T;
   - T is a real ancestor of the install commit;
   - the request's source is the install commit;
   - the request targets the trunk;
   then what the host merges is exactly `diff(T, install commit)`, the diff that was proved. For that reason no host file-list comparison is required. A push that goes somewhere else, or a remote that is renamed or rewritten mid-run, shows up as a source-commit or trunk-head mismatch and is refused.
6. (SHI-55) The trunk's *name* still comes from `BASE_BRANCH` in `pipeline.env` (working tree = committed), as the guard reads it today for every command. Treating `pipeline.env` as a trust root generally, and constraining what an unreviewed install may put in it, is follow-up NEW-1, not SHI-55 (see Delivery notes).
7. (SHI-55) The guard stays network-free by owner decision, so its install check is a local pre-check. The guard's security contribution is FR-5a–c and FR-5e: only the plugin's own route may run, and it must run alone. The route then carries the proof.

## Delivery notes
- Flags / env: no new `pipeline.env` key. Only the existing test doubles are used, from the process environment (FR-18). The reference lookup (FR-4) is the engineer's to implement within its constraints. The install set stays defined in one place (`init.sh --list` / `--verify-install`). For FR-17 the verifier accepts T from the route, and the guard's pre-check keeps using the local trunk ref. The mechanism is the engineer's.
- Rollout order: SHI-47, then SHI-48 and SHI-49 in parallel, then SHI-50 (all done). SHI-55 is the rework: it is fixed on the ticket branch, re-merged to master, and re-promoted through dev, qa and staging for re-test. Existing installs get the route and the new guard on their next `/pipeline-init` re-run.
- Known limits, stated in the docs and CHANGELOG:
  - The guard sees agent tool calls only. A script that calls the host API internally is not examined (unchanged). In the same class: git's own per-repository configuration and hooks run during the route's fetch and push. They are project state, like any script an agent writes. FR-17.4 still refuses the merge if they change what is being merged.
  - The route acts on whichever host repository the project's remote names. It can only land a verified install there, checked against that repository's real trunk.
  - The owner's consent (R5) is enforced by `/pipeline-init`'s instructions, not by the guard.
  - The install request's Pipeline Gate check shows as failed. That is expected until SHI-46.
  - The reference is only as trustworthy as the user's plugin install.
  - `pipeline.env` is class F (free content) and is sourced by most pipeline scripts, by the guard for every command, and by CI's `gate.sh`. An unreviewed install merge can therefore carry executable content in it. This is follow-up NEW-1; whether go-live waits for it is clarifications Q-1.
- CONTEXT.md "stop and ask before altering the write-boundary hooks": the owner approved this change in product.md and approved the SHI-55 direction on 2026-09-28.
- CONTEXT.md Stack test list lacks `test_install_merge.sh` and `test_adapters.sh` (PO to update; noted in signoff.md).
