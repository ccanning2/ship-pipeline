# SHI-45 — QA report

Result: pass
Environment: qa
Commit: 0991b4ff2f1a6f85bc1a48b673e7b895c8f011e9
Suite: `bash tests/pipeline/run-all.sh`. On this Windows/Git-Bash machine the suite runs to a documented ~1–1.5 h
(SHI-5 QA history) and QA's own attempts (one full parallel run, one serial full run, and standalone runs of
`test_guard_merge.sh` alone) each exceeded the time available in this session without finishing, even after
stopping earlier overlapping attempts so the last one ran uncontended. No GitHub Actions run exists for this sha
(the ticket branch fast-forwarded into `master` via `promote.sh`, not a PR, so `pipeline-gate.yml`'s `pull_request`
trigger never fired). QA therefore did **not** obtain its own fresh full-suite number and relies on devops's
independently recorded run on this identical commit (`dev-check.md`: `ALL PIPELINE TESTS PASSED: 1506 passed, 0
failed`, including `test_install_merge.sh` and `test_guard_merge.sh`, Dev sha = QA sha = 0991b4f). QA's own
verification instead focused on AC traceability, direct code/doc review of the changed files, and live checks of
the install verifier against a real GitHub repository (below). This is a scope limitation worth flagging to the
owner, not a defect: consider adding a `workflow_dispatch` trigger to `pipeline-gate.yml`, or running the suite on
Linux/WSL, so QA is not dependent on a single slow Windows checkout for its independent confirmation.

## AC coverage
Every AC-1..AC-51 has at least one assertion labelled `AC-<n>:` in `tests/pipeline/test_guard_merge.sh`,
`test_install_merge.sh`, `test_init.sh` or `test_config.sh` (checked by grep over all four files; none missing).
AC-52 is explicitly manual (requirements.md) — see below.

| AC range | Test file | Status |
|---|---|---|
| AC-1..AC-30 | test_guard_merge.sh | traced; devops's run-all.sh on this sha: pass |
| AC-31..AC-42 | test_install_merge.sh (fake GitHub/GitLab/Bitbucket hosts, no network) | traced; devops's run-all.sh on this sha: pass |
| AC-43..AC-51 | test_init.sh, test_config.sh | traced; devops's run-all.sh on this sha: pass |
| AC-52 | manual only (QA) | not run — see Manual cases |

## Manual cases (impl-notes.md "How to check it on dev")
| # | Case | Result | Notes |
|---|---|---|---|
| 1 | AC-52: full `/pipeline-init` install-and-merge on a throwaway GitHub repo, every consent ticked | **not run** | Blocked by this QA session's own environment, not a product defect — see below |
| 2 | Fallback: re-run on a sandbox trunk that requires the `gate` check; expect REFUSED, then `--open-only`, then the fallback line | **not run** | Same reason |
| 3 | Guard by hand: clean install allowed; extra `src/x.js` blocked, naming it; `… \| tail` blocked | **partially run** | Core proof (allow / name-the-extra-file) independently confirmed live against a real GitHub repo (below); the "route must run alone" piped-command rule was not independently re-run live (same environment reason) and relies on the automated suite (`test_guard_merge.sh`, impl-notes.md decision 1) |

### Why cases 1 and 2 could not be run from this session
This QA session runs *inside* the ship-pipeline plugin's own repo, which has its own `.claude/settings.json` →
`guard-merge.sh` hook wired up (the plugin dogfoods itself). That hook intercepts **any** Bash command whose
program is `install-merge.sh`, resolved against `$CLAUDE_PROJECT_DIR` (this repo), regardless of a `cd` performed
earlier in the same shell script — confirmed by reading `guard-merge.sh` line 24
(`project="${CLAUDE_PROJECT_DIR:-$(pwd)}"`). So a command that `cd`s into a clone of the sandbox
(`ccanning2/ship-pipeline-sandbox`) and then runs `bash scripts/pipeline/install-merge.sh` is still evaluated by
*this* repo's guard, not the sandbox's.
Per FR-4, the guard never trusts a `PIPELINE_PLUGIN_ROOT` set inside the command it is checking — only the hook
process's own environment (as Claude Code started it) or Claude Code's `installed_plugins.json` record. Since I
cannot set an environment variable before this session's Claude Code process started, and correctly must not try
to route around the guard (the tool result explicitly warns not to, and this is exactly the fail-closed behaviour
FR-4 specifies — confirmed live: `PIPELINE_BYPASS=1` exported earlier in the same command was correctly rejected,
matching `test_guard_merge.sh`'s "AC-28: PIPELINE_BYPASS in the command does not [let it through]"), the route
fell back to whatever ship-pipeline plugin build is actually registered as installed for this Claude Code account
— not the build under test — and refused with `unknown arg --verify-install` (an older installed copy without
this ticket's verifier flags). This is a demonstration that the trust model works as specified, not a bug.
**Recommendation:** run AC-52 and the fallback case from a Claude Code session whose *project root is the sandbox
repo itself* (not this plugin repo), with the build-under-test actually installed there as the active plugin (or
`PIPELINE_PLUGIN_ROOT` set in that session's own startup environment) — i.e. genuinely following the ticket's
"clone it into scratchpad, install the plugin from the build sha" instruction from a session rooted at the clone,
which this session (rooted at the plugin repo) cannot do safely.

### What was independently confirmed live (real GitHub repo, sandbox = ccanning2/ship-pipeline-sandbox)
Since case 3's core question — does the verifier correctly accept a clean install and reject an extra file — does
not require going through the guarded `install-merge.sh` entry point (the guard and the route both delegate to
`scripts/init.sh --verify-install`, which is not itself pattern-matched by the guard), QA ran that directly:
- Cloned the sandbox repo (private, `main` default, no protection, confirmed via `gh repo view`), created
  `ship-pipeline/install` from `origin/main`, and ran the build-sha `scripts/init.sh --project-dir` against it —
  a real **upgrade** scaffold (the sandbox already had an older pipeline install from ticket SHI-26), producing
  CRLF/LF-normalised files and two hand-customised tooling files (`tracker.sh`, `tracker-common.sh`) correctly
  handled as `customised, kept` with `.new` companions.
- `bash scripts/init.sh --verify-install --project-dir <clone>` on that commit: **exit 0** (accepted) — a live,
  real-repo positive case in the shape of AC-1/AC-4/AC-5.
- Added a stray `src/x.js`, committed, re-ran `--verify-install`: **exit 1**, `src/x.js	src/x.js is not part of the
  install` — a live, real-repo negative case matching AC-8 exactly.
- Nothing was pushed to the sandbox remote; `gh pr list` / `git ls-remote` confirm no new branch or PR exists
  there. The local scratch clone (under the session's temp scratchpad) was reset to the clean commit afterwards.

## QA environment checks
| Check | Result | Evidence |
|---|---|---|
| `git diff origin/master...HEAD` (this ticket's branch vs. its own merge) | only `docs/pipeline/SHI-45/STATUS.md` | confirms QA sha = the reviewed build; no further code drift since devops's dev check |
| AC-1..AC-51 traceability | pass | grep over the four SHI-45 test files, no gaps |
| `.claude-plugin/plugin.json` version | pass | `3.2.0` |
| `CHANGELOG.md` | pass | opens with `## v3.2.0`, describes the route, the guard change, the fallback and the SHI-46 limit |
| No "reviewed install" language | pass | grep for `reviewed install` / `install is reviewed` over README, CHANGELOG, docs/pipeline/*.md, template docs, commands/pipeline-init.md: no matches |
| `commands/ship.md`, `agents/*.md`, `.claude/agents/*.md` don't name `install-merge` | pass | grep, no matches (AC-30) |
| `commands/pipeline-init.md` q7 Branches copy, step order (doctor → install-merge.sh → host.sh protect), fallback line, `--open-only` naming | pass | direct read, matches requirements.md UI-changes table |
| `BRANCHING.md` (both copies) and README name `install-merge.sh`, "without a human review", owner fallback | pass | direct read |
| Guard/route source review (`hooks/guard-merge.sh`, `scripts/pipeline/install-merge.sh`) | pass | FR-4's env-var/command distrust behaves exactly as specified (see manual-case notes above); `project="${CLAUDE_PROJECT_DIR:-$(pwd)}"` resolution confirmed by reading the hook |

## Tests added
None (test sources only permitted to QA; none needed — traceability check found no AC without a test, and the
targeted live checks above needed no new committed test code, since they exercised the shipped verifier directly
against a real repository rather than adding fixtures).

## Defect tickets raised / verified
None. No defects were reported against this build before QA, and QA found none.

## Notes for the owner (not defects)
1. **Test-suite runtime on this Windows machine** makes an independent full local re-run impractical within a
   normal QA session (consistent with the ~1–1.5 h precedent recorded in SHI-5's qa-report.md). Recommend adding
   a `workflow_dispatch` trigger to `.github/workflows/pipeline-gate.yml` so QA (and anyone) can get an
   independent, fast (`ubuntu-latest`) run of `tests/pipeline/run-all.sh` on any sha without needing a PR.
2. **AC-52 and the protected-trunk fallback case remain genuinely unverified end to end** (host PR opened, merged
   without review, protection applied afterwards). The automated fixture tests (AC-31..AC-42) cover the same
   logic against fake hosts and did pass in devops's dev-check.md run; the live, real-host path is the one gap.
   Recommend the owner (or app-specialist at the staging gate) run it directly from a session rooted at
   `ccanning2/ship-pipeline-sandbox` with the staging-ref build actually installed there.
