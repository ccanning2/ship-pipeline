# SHI-45 — QA report (rework loop 1)

Result: pass
Environment: qa
Commit: 6a619f723cf90822c01d6975aaac6898c3fd265a

This is the re-test pass after rework loop 1: defect SHI-55 (High, found on staging at 0991b4f) fixed, plus new eng
ticket SHI-57 (R1c-2, `pipeline.env` content rule) built, both in commit d50b581, merged to `master` and now on
`staging` (qa) at 6a619f7 (dev-check.md, releases.md). Requirements.md amended (19 FRs, 76 ACs; FR-17, FR-18, FR-5d,
FR-5e, NFR-2, AC-53..AC-63 for SHI-55; FR-19, AC-64..AC-76 for SHI-57). Owner-accepted open item unchanged: the live
AC-52 install-and-merge and protected-trunk fallback on a real host are not run here (recorded below, not blocking).

## Suite run
Full `bash tests/pipeline/run-all.sh` was **not** re-run in this session (constraint: 45+ min on this machine, and
an earlier session's run left ~100 orphaned processes last time). Relied on devops's independently recorded run on
this identical sha (`dev-check.md`: `ALL PIPELINE TESTS PASSED: 1930 passed, 0 failed`, including
`test_install_merge.sh` and `test_guard_merge.sh`). QA ran the two targeted files itself, one at a time, no
overlapping runs, each finished before the next started:
- `bash tests/pipeline/test_guard_merge.sh`: **298 passed, 0 failed** (matches impl-notes.md's stated count exactly;
  was 220 before rework).
- `bash tests/pipeline/test_install_merge.sh`: **390 passed, 0 failed** (matches impl-notes.md's stated count
  exactly; was 73 before rework).
Both processes were confirmed finished (no residual `bash`/`git` test processes) before moving on. One orphaned
waiter from an earlier, interrupted session (a stale `run-all.sh` summary loop, PID unrelated to this session's own
runs) was found and terminated; it was idle (polling only) and not a duplicate test run.

## SHI-55 — re-test (independent repro, not the automated suite)
Reproduced the original defect's exact steps from signoff.md, from a fresh fixture (bare local `origin`, fake
GitHub host, `PIPELINE_PLUGIN_ROOT` = a worktree at 6a619f7), independent of `test_install_merge.sh`:
1. Fresh repo, `origin/master` = one file, install branch built and committed. Guard on the route: exit 0 (clean
   install, as expected).
2. `src/Backdoor.java` committed on a branch `evil` from `origin/master`; the install branch rebased onto `evil`.
   Guard on the route: exit 2, naming `src/Backdoor.java` (as expected — ordinary, non-forged case).
3. `git update-ref refs/remotes/origin/master evil` (the forged local ref from the original defect). Guard
   pre-check: still may allow it — this is by design (FR-5d, network-free pre-check; AC-53 says explicitly "the
   guard's local pre-check may allow this command; what must hold is the outcome").
4. **The route itself**, run directly (`bash scripts/pipeline/install-merge.sh`): **exits 4**,
   `NOT-INSTALL src/Backdoor.java: src/Backdoor.java is not part of the install`. The fake host log shows only the
   trunk-head read (`gh repo view`, `gh api repos/o/r/branches/master`) — no push, no pull request opened, no merge
   call. `refs/heads/ship-pipeline/install` was never created on the bare origin. The real `origin/master` is
   unchanged.

Before the fix (0991b4f) this same sequence let the route merge the backdoor file with no ticket (signoff.md). On
6a619f7 the route is anchored to what the host reports for the trunk, not the agent-settable local ref, exactly as
FR-17 specifies. **SHI-55 is fixed** — moved to `verified` in the tracker with the repro and evidence in a comment.

## SHI-57 — re-test (independent repro, not the automated suite)
Ran `scripts/init.sh --verify-install` directly (bypassing the fixture harness) against fresh install-branch
fixtures, one change to the committed `pipeline.env` at a time:
| Case | Committed pipeline.env change | Result |
|---|---|---|
| Unknown key | `FOO="x"` appended | exit 1, `'FOO' is not a setting in the plugin's pipeline.env template` |
| Command line | `touch /tmp/shi57_marker` appended | exit 1, "not a comment, a blank line or a plain KEY=\"value\" setting"; `/tmp/shi57_marker` was never created — confirms `pipeline.env` is read as data, never executed |
| `export` | `export BASE_BRANCH="master"` | exit 1, `'export' is not allowed` |
| Duplicate key | `BASE_BRANCH="master"` appended a second time | exit 1, `'BASE_BRANCH' is set more than once (first on line 9)` |
| Substitution | `PROJECT_NAME="$(touch /tmp/shi57_marker2)"` | exit 1, "the value of 'PROJECT_NAME' is not a plain value…"; `/tmp/shi57_marker2` was never created |
| Unchanged (positive) | rendered file exactly as `init.sh` wrote it | exit 0 (merges) |

All five negative cases fail closed with a reason naming the line and, where applicable, the key — never the value
— and none of the injected commands or substitutions executed. The positive case passes untouched. **SHI-57 works
as specified.**

## AC coverage (AC-53..AC-76, new/amended this loop)
Every AC has at least one assertion labelled `AC-<n>:` in `test_guard_merge.sh` or `test_install_merge.sh` (route
and guard sides), except AC-63/AC-75 (doc-only) and AC-76 (delivery/doc-only), which are in `test_init.sh` — checked
by grep, none missing:

| AC range | What | Test file(s) | Status |
|---|---|---|---|
| AC-53..AC-55 | forged ref, PIPELINE_REMOTE second spelling, on all 3 fakes | test_install_merge.sh (+ guard side for AC-53) | traced; green |
| AC-56..AC-58 | trunk moved, wrong target, host unreachable | test_install_merge.sh | traced; green |
| AC-59 | pipeline.env liar + marker, working-tree only and committed | test_install_merge.sh | traced; green |
| AC-60..AC-61 | grafts/replace-refs/shallow; stale local ref still merges | test_install_merge.sh | traced; green |
| AC-62 | guard network-free with the route cases | test_guard_merge.sh | traced; green |
| AC-63 | docs (pipeline-init.md, both BRANCHING.md, CHANGELOG v3.2.0) | test_init.sh + direct doc read | traced; green |
| AC-64..AC-74 | FR-19 positive/negative cases (guard + route) | test_guard_merge.sh, test_install_merge.sh | traced; green |
| AC-75 | docs (BRANCHING.md, CHANGELOG, SHI-56 named) | test_init.sh + direct doc read | traced; green |
| AC-76 | CONTEXT.md Tests bullet lists every run-all.sh file | test_init.sh + direct doc read | traced; green |

Direct doc reads (not just the test assertions) also confirm: both `docs/pipeline/BRANCHING.md` and
`template/docs/pipeline/BRANCHING.md` carry the host-anchored-check sentence and the `pipeline.env`/"falls back to
the owner" sentence; `CHANGELOG.md`'s `## v3.2.0` section carries both, plus SHI-56 named in the known-limits line;
`docs/pipeline/CONTEXT.md`'s `Tests:` bullet lists all 11 files including `test_adapters.sh` and
`test_install_merge.sh`.

## Regression check (earlier ACs, AC-1..AC-52)
- `scripts/pipeline/hooks/guard-merge.sh` is **byte-identical** between 0991b4f and 6a619f7 (`git diff` empty), so
  the AC-1..AC-30 guard behaviour QA already verified at the previous pass carries no code risk from this rework;
  `test_guard_merge.sh`'s full 298/298 pass (which includes the original AC-1..AC-30 lines, untouched per AC-24)
  confirms no regression.
- `test_install_merge.sh`'s AC-31..AC-42 lines are unchanged except the AC-38 assertion, which requirements.md
  itself amends for this loop ("no host call" -> "the trunk-head read is the only host call") — matches the new
  host-anchored design, not a regression.
- `.claude-plugin/plugin.json` still `3.2.0`; `CHANGELOG.md` still opens with `## v3.2.0`; no "reviewed install"
  language (grep, no matches); `commands/ship.md` / `agents/*.md` / `.claude/agents/*.md` still don't name
  `install-merge` (AC-30, in the 298/298 guard run).
- `docs/pipeline/SHI-45/tickets.md` matches the tracker's children listing (checked via `tracker.sh children`).

## Open items (owner-accepted, not blocking)
- **AC-52** (live `/pipeline-init` install-and-merge on a throwaway GitHub repo) and the **protected-trunk
  fallback** case are not run from a real host in this session — same constraint as the previous QA pass and
  dev-check.md: this session's own guard hook intercepts any `install-merge.sh` call for *this* repo regardless of
  target directory, and correctly refuses to trust a command-line `PIPELINE_PLUGIN_ROOT` override (FR-4), so it
  cannot exercise the build under test against a live sandbox repo from inside this session. The owner has already
  accepted this as an open item to check by hand (tracker comment, 2026-09-28T10:33Z) and it is unchanged by this
  rework loop. Recommend running it from a session rooted at the sandbox repo with the staging-ref build actually
  installed there, per the previous qa-report's recommendation.

## Tests added
None. Traceability check found no AC-53..AC-76 without a test; the independent repro checks above needed no new
committed test code (they exercised the shipped route/verifier directly, mirroring the fixture harness already in
`tests/pipeline/lib.sh` but run as standalone scratch scripts, not committed).

## Defect tickets raised / verified
- **SHI-55** (defect, High, staging): **verified**. Independent repro confirms the fix; comment and evidence added
  to the tracker ticket; moved `fixed` -> `verified`.

No new defects found in this pass.

## Notes for the owner (not defects, carried from the previous pass)
1. Test-suite runtime on this Windows machine still makes a fresh, unassisted full local re-run impractical within
   a normal QA session; QA continues to rely on devops's `dev-check.md` full-suite number plus its own targeted
   file runs (this pass: the two files touched by this rework, both matching the expected counts exactly). The
   `workflow_dispatch` recommendation from the previous pass stands.
2. AC-52 and the protected-trunk fallback remain genuinely unverified end to end (see Open items above).
