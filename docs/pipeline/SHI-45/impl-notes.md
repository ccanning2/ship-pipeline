# SHI-45 — Implementation notes

Status: ready-for-dev

## Rework 1 (SHI-55 defect, SHI-57 eng)

### SHI-55: the route's proof is anchored to the host's trunk (FR-17, FR-18, FR-5d/e, NFR-2)
- **`scripts/pipeline/install-merge.sh`**, merge form:
  - It reads T, the trunk's head, from the host (`host.sh branch-head <trunk>`), once, before any push or request call. A failed read, or an answer that is not a full sha, gives `REFUSED <web url> the trunk tip could not be read from the host (<reason>)`, exit 3.
  - If commit T is not here, it fetches the trunk and looks T up by id only. Still missing gives `REFUSED <web url> the host's trunk tip <T> could not be fetched`.
  - It runs the plugin's `init.sh --verify-install --trunk-tip T` (exit 4 `NOT-INSTALL`). "Nothing to merge" and the upgrade title also use T.
  - It pushes `<install sha>:refs/heads/ship-pipeline/install`, not `HEAD`.
  - After the wait and right before the merge, it re-reads the request (source commit and target branch) and T. A request into another branch, or a trunk that moved, is refused with exit 3 and no merge call.
  - It exports `PIPELINE_ENV_AS_DATA=1`, `GIT_NO_REPLACE_OBJECTS=1` and a nonexistent `GIT_GRAFT_FILE`. Ancestry checks use `-c core.commitGraph=false`.
  - The local-ref "nothing to merge" early exit stays. It can only refuse (exit 1), never allow; AC-61 shows a missing or stale local ref still merges.
  - `--open-only` reads no T. Its only new behaviour is pushing the recorded sha.
- **`scripts/init.sh --verify-install`**:
  - New `--trunk-tip SHA` (merge form only). Without it the local `<remote>/<trunk>` ref stands in. That is now documented as the guard's network-free pre-check.
  - Real history only: `--no-replace-objects`, grafts off, commit-graph off. A shallow boundary counts as "not an ancestor".
  - FR-3.2 now compares `BASE_BRANCH`, `GIT_HOST`, `GIT_HOST_URL` and `PIPELINE_REMOTE` (committed vs working tree, after defaults). The reason copy is `... at HEAD says <KEY>="<v>", but the working tree says "<w>"`.
- **`base-ref.sh`**: with `PIPELINE_ENV_AS_DATA=1`, pipeline.env is parsed, never sourced, using `init.sh`'s `declared_value` rules. Process-env values of those keys are ignored. New `--value KEY`, for the FR-18 keys only.
- **`lib/host-common.sh`**: in data mode, `GIT_HOST_URL` comes from `base-ref.sh --value` and nothing is sourced, so the test doubles and `PIPELINE_WAIT_TRIES` count only from the environment.
- **Adapters (all three)**:
  - New read-only verb `branch-head <branch>`: GitHub `repos/<slug>/branches/<b>` `.commit.sha`, GitLab `repository/branches/<b>` `.commit.id`, Bitbucket `refs/branches/<b>` `.target.hash`.
  - `request-info` now prints a third field, the target branch.
  - The guard decides `branch-head` like the other read verbs (it is not gated).
- **Guard**: code unchanged. It stays network-free (AC-62). FR-5e was already implemented.
- **Docs**:
  - `commands/pipeline-init.md`: the pre-check wording, the new REFUSED causes, and the "not opened" Impact line with when to report it.
  - Both `BRANCHING.md` copies and CHANGELOG v3.2.0: the host-anchored sentence and the fallback.
  - CHANGELOG known limits name SHI-56.
  - `plugin.json` stays 3.2.0.

### SHI-57: pipeline.env content rule, class E (FR-19, R1c-2)
- `init.sh --list` reports `scripts/pipeline/pipeline.env<TAB>E<TAB><reference template path>`. The verifier reads the allowed keys and the shipped `PIPELINE_TICKET_REGEX` line from that template at check time. No second list exists anywhere.
- `env_rule` in `init.sh` runs only when the diff adds `pipeline.env` or changes its content (a mode-only change is not examined). It runs before FR-3.2, so a command line is reported as FR-19, not as a config mismatch.
- It enforces lines of these kinds only: blank lines, comments, a plain `KEY=value` at column 1 (double-quoted with no `"`, `$`, backtick or `\`; single-quoted; empty; or bare `[A-Za-z0-9_./:@%+,-]`), optionally followed by whitespace and a `#` comment, and the template's regex line exactly. Each key may appear once.
- Reason order: export, unknown key, value not plain, duplicate, other shape. Reasons name the line and at most the key, never the value.
- A missing template fails closed: `scripts/pipeline/pipeline.env: the plugin's pipeline.env template could not be read`.
- The guard and the route share it, because it lives in the one verifier.
- **CONTEXT.md**: the `Tests:` bullet now lists `test_adapters.sh` and `test_install_merge.sh` (AC-76, checked in `test_init.sh`).

### Tests (rework)
- Suite before: 1506  after: 1930, all green (`bash tests/pipeline/run-all.sh`, ALL PIPELINE TESTS PASSED). By file: config 241, init 369, gate 175, promote 105, intake/status 135, allow-paths 25, guard 298 (was 220), doctor 55, deploy scripts 18, adapters 119, install-merge 390 (was 73).
- `test_guard_merge.sh` and `test_adapters.sh`: added lines only (`git diff d7815e3` shows 0 removed lines, AC-24).
- `test_install_merge.sh`: the fakes gained answers for `branch-head` (from the bare origin, or from `$FK/tip`, `$FK/tip2`, `$FK/tipfail`) and a target branch in `request-info`. The three existing request-info fake lines were edited for that. The AC-38 assertion changed from "no host call" to "the trunk-head read is the only host call", as amended AC-38 requires. No other existing line changed.
- New cases:
  - AC-53/54/55/59 on all three fakes: the forged ref, `PIPELINE_REMOTE=fork`, and a liar plus `touch` in the working-tree and in the committed pipeline.env.
  - AC-56/57/58 on all three fakes.
  - AC-16 and AC-17 route side, AC-60 (replace ref, graft, shallow), AC-61, AC-34 with no local ref, AC-31/32 read ordering.
  - FR-19 cases AC-64..AC-74 in both the guard and the route.
  - `init.sh`/`base-ref.sh` unit checks for `--trunk-tip`, `--value` and data mode, plus AC-63, AC-75 and AC-76 in `test_init.sh`.

### How to check it on dev (install from the master ref into a throwaway repo)
- `bash tests/pipeline/run-all.sh`.
- The SHI-55 repro from signoff.md on a fixture:
  1. Run `git update-ref refs/remotes/origin/master evil`, then run the route directly with the fake host.
  2. Expect `NOT-INSTALL src/Backdoor.java: …`, exit 4, with no push and no request.
  3. The guard's pre-check may still allow the command. That is by design (network-free).
- Put `touch /tmp/x` in the working-tree pipeline.env and run the route: `/tmp/x` is never created.
- Commit `FOO="x"` in pipeline.env on an install branch: the guard blocks with `scripts/pipeline/pipeline.env line <n>: 'FOO' is not a setting in the plugin's pipeline.env template`.

### For devops
- No CI, deploy or infra file changes. `run-all.sh` is unchanged.

### Known limits (unchanged scope)
- The trunk's name still comes from `BASE_BRANCH` (working tree = committed). If both omit it, `base-ref.sh` falls back to `<remote>/HEAD`. Wider pipeline.env hardening is SHI-56.
- The GitHub trunk-head read resolves the repository with `gh repo view` (as `web-url` already did), so the host log shows that call too.

## Tickets worked
- SHI-47 (eng): install verifier: `scripts/init.sh --verify-install` and `--list`
- SHI-48 (eng): guard recognition of `install-merge.sh`, R6 regression
- SHI-49 (eng): `scripts/pipeline/install-merge.sh` route and the `request-*` host verbs
- SHI-50 (eng): `/pipeline-init` flow and consent copy, docs, v3.2.0

## Changes
- **`scripts/init.sh`**, the one definition of the install set (FR-3, FR-4, NFR-1..3):
  - `--list DIR`: prints `<path> TAB <class> TAB <expected copy>` for every file the install writes, for the configuration in `--project-dir`'s `pipeline.env`. Classes: T tooling, S safety-bearing project file, G `.gitlab-ci.yml`, F free project file. It renders into DIR and writes nothing into the project. The install and `--list` share `render`, `copy_tooling` and `copy_owned`, and `.gitlab-ci.yml` generation is one function (`gitlab_ci`) used by both the install and the verifier.
  - `--verify-install [--open-only]`: the proof. It always runs from the plugin's copy. It prints `<path> TAB <reason>` and exits 1 on the first failure.
    - It checks the route's six files in the working tree.
    - Then the install branch, `<remote>/<trunk>` as an ancestor, the committed `BASE_BRANCH`, and the `--no-renames --no-abbrev` raw diff against `--list` for the committed configuration.
    - Contents are compared by raw git blob id with every CR removed. It uses one awk pass and one `hash-object --no-filters --stdin-paths`, and `--no-replace-objects` everywhere, so `.gitattributes` filters, textconv and replace refs cannot fake a match.
    - Deletions pass only for retired tooling: a path under the retire prefixes, not in the current set, and recorded in the trunk tip's `.install-manifest`, or a stale `.new`, or `.gitignore.pipeline`.
    - Any error fails closed.
  - `declared_value` now reads `pipeline.env` once and matches in pure bash with the same semantics, because process cost on Git Bash dominated. The existing QA2 parser tests all pass unchanged.
- **`scripts/pipeline/install-merge.sh`** (new tooling file, in the tooling loop, the manifest and the header list): `install-merge.sh` merges, `--open-only` only opens. Anything else is exit 1 with no call.
  - Before any push it runs the plugin's `--verify-install` (exit 4 `NOT-INSTALL`).
  - It pushes `HEAD:refs/heads/ship-pipeline/install` without force, then `host.sh request-open` (or reuses the open request).
  - It waits (bounded by `PIPELINE_WAIT_TRIES`) while `request-info` says `checking`. It refuses if the source commit is not the install commit, then makes one `request-merge <id> <sha>`.
  - It prints `MERGED` / `REFUSED` (exit 3) / `OPENED`, then fast-forwards the local trunk and deletes the install branch (a failure there is a `NOTE`).
- **Host adapters** (all three, and `lib/host-common.sh`): new verbs.
  - `request-open <branch> <base> <title> <body>` prints `<id> <url>` and adds no label.
  - `request-info <id>` prints `<source sha> <ready|checking|blocked>`.
  - `request-merge <id> <sha>`: GitHub and GitLab pin the sha. Bitbucket is re-read by the route first. A refusal is one line and exit 3.
  - No protection, ruleset, label or admin call exists in these verbs.
- **`hooks/guard-merge.sh`** (within R1–R8):
  - A segment whose program is `install-merge.sh` is recorded and decided after every other segment, so AC-27's push is blocked as a push.
  - It is allowed only when all of these hold: the path resolves (against the hook input's `cwd`) to the project's `scripts/pipeline/install-merge.sh`; the arguments are none or exactly `--open-only`; the reference is found in the hook's environment (`PIPELINE_PLUGIN_ROOT`) or `installed_plugins.json` (exactly one `ship-pipeline@*` install path, else fail closed); the reference's `init.sh --verify-install` passes; and the route runs alone.
  - The block copy and the `no_ticket` "Ways forward" line are as in requirements.md.
- **Docs**: `commands/pipeline-init.md` (q7 Branches copy, step 5 no longer protects, step 8 ticked/unticked flow, Impact lines), both `BRANCHING.md`, README (Work without a ticket, Enforcement, layout), CHANGELOG `v3.2.0`, `plugin.json` 3.2.0 (and the version pin in `tests/pipeline/test_config.sh`).

## Decisions the owner should know (all stricter, none loosens R1–R8)
1. **The route must run on its own** (no other command, no variable assignment, no pipe; a trailing `2>&1` is fine). The requirements say "other segments are checked as today". The code is stricter: in the same call, `git commit …; bash scripts/pipeline/install-merge.sh` or `cp evil scripts/pipeline/install-merge.sh && …` would change the state after the guard checked it. `/pipeline-init` step 8 says to run it alone.
2. **Guard tightening outside the route (R6)**: `FOO=/x git push origin HEAD:master` used to be read as a program named `x`, so the push was never examined. This was an existing bypass, and AC-23's `VAR=/path bash install-merge.sh` would have slipped through the same way. An assignment is now recognised on the whole word. Every existing test keeps its exit code.
3. **`host.sh request-merge` needs a ticket** (dev gate, like `host.sh merge`). Otherwise the new verb would be an ungated merge.
4. **`scripts/pipeline/tracker.map` is class F.** The requirements table omits it, but `tracker.sh setup` writes it on the default path, so the default install would otherwise always fall back. It is data (state to status names), never sourced.
5. **AC-25's bare `git push`**: on the install branch it pushes the install branch itself, not the trunk, so R6 (unchanged decisions) keeps it allowed. The test says so explicitly. Bare `git push` on master is still blocked (AC-29).
6. **AC-14**: a deletion can only be seen where the trunk already has the file, so it is tested on the upgrade fixture. A fresh install commit that simply omits a tooling file is not a deletion. It passes the verifier, and the doctor reports the missing file.
7. `/pipeline-init` cannot name the install branch literally: the persona and command leak test forbids the plugin name in `commands/*.md`. Step 8 reads the name from `install_branch=` in the route.

## How to check it on dev (install from the `master` ref into a throwaway repo)
- `bash tests/pipeline/run-all.sh`: the new `test_install_merge.sh` runs with the fake hosts, and `test_guard_merge.sh` covers AC-1..AC-30.
- Manual (AC-52, for QA): a throwaway GitHub repo with no protection. Run `/pipeline-init` from the ref with every consent ticked. Expected: after the sign-in there is nothing to do; `git log origin/master` shows `chore: install ship pipeline` merged; protection is applied afterwards; Impact reads `Install merged into master: <url>`.
- Fallback: the same on a repo whose trunk already requires the `gate` check. Expected: `REFUSED`, then `--open-only`, then the fallback line. No protection, label or admin call.
- Guard by hand, in an installed project on the install branch:
  - `bash scripts/pipeline/install-merge.sh` is allowed only for a clean install.
  - Add `src/x.js` to the commit and it is blocked, naming the file.
  - `… | tail` is blocked (the route must run alone).

## CI/CD & infra changes
- none. **For devops:** nothing in `.github/workflows/*`, `scripts/deploy/*` or infra changes. `tests/pipeline/run-all.sh` gained `test_install_merge.sh`. CONTEXT.md's Stack section lists the test files; the PO should add `test_install_merge.sh` there (the ticket says the PO updates it).

## Migrations
- none. Existing installs get `install-merge.sh` and the new guard on their next `/pipeline-init` re-run.

## Config / env vars
- `PIPELINE_PLUGIN_ROOT`: read from the hook's own environment (like `PIPELINE_BYPASS`), and by the route when run from a terminal. It is never taken from the command. Tests use it. No new `pipeline.env` key.

## Tests
Suite before: 1256  after: 1506 (all green, `bash tests/pipeline/run-all.sh`)
- `test_config.sh`: the release-version pin moves from 3.1.0 to 3.2.0 and the changelog heading loop gains `v3.2.0`, as every release does (FR-14). No other existing test line changed.
- Review fix before commit: `lib/host-common.sh` (`refused`) and `init.sh` (`--list`) held literal CR, tab and newline bytes inside quoted strings. They are now `\r`, `\t`, `\n` escapes, so a CRLF or re-encoding checkout cannot change what they do.
- New: `tests/pipeline/test_install_merge.sh` (73 checks: AC-31..AC-42 on GitHub, GitLab and Bitbucket fakes). Appended to `test_guard_merge.sh` (AC-1..AC-30; existing lines untouched, AC-24 checks this) and `test_init.sh` (AC-43..AC-51, `--list`).
- Timing on this Windows machine: the guard on the route takes about 5–6 s (one `--list` run is about 2 s). Any other command costs the same as before (no extra process).

## Docs updated
- [x] README.md  - [x] docs/pipeline/BRANCHING.md (+ template)  - [x] CHANGELOG.md  - [x] commands/pipeline-init.md  - [ ] TICKETS.md / CLOUD.md (no change needed)

## Known limitations
- The install request's Pipeline Gate check shows as failed (no ticket). An upgrade on a trunk that already requires it falls back to the owner until SHI-46.
- The guard sees agent tool calls only. The reference is only as trustworthy as the plugin install and `installed_plugins.json` on the machine, which is the trust model FR-4 accepts.
- `PIPELINE_PLUGIN_ROOT` has the same trust model as `PIPELINE_BYPASS`: whatever sets Claude Code's own environment (including an `env` block in a settings file Claude Code loads) sets it. That is unchanged by this ticket. A persona whose `allow-paths.sh` globs leave out `.claude/settings.json` cannot write it; any other session could, so the owner should treat an unexpected edit there as they would one adding `PIPELINE_BYPASS`.
- The guard splits a command at `$(`, `)`, `;`, `|`, `&`, so a word such as `scripts/pipeline/install-merge.sh` right after a `)` is read as a route call and checked (it fails closed; nothing is allowed that should not be).
- A remote install branch left over from an earlier failed run, which the new commit does not descend from, is rejected on push (no force). The owner deletes it.
