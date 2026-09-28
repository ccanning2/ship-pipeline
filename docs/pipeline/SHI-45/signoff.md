# SHI-45 — Staging sign-off

Decision: blocked
Environment: staging
Commit: 0991b4ff2f1a6f85bc1a48b673e7b895c8f011e9
Signed: 2026-09-28

Staging here is the `staging` ref at the sha above (PIPELINE_HAS_DEPLOY_ENVS=no; the artefact is plugin v3.2.0).
Checked in a clean detached worktree at that sha in the session scratchpad. Nothing was pushed; no repo or PR created.

## Test re-run
Suite: `bash tests/pipeline/run-all.sh` NOT re-run in full (owner instruction: over 1 h on this machine, which was
still loaded by earlier aborted runs). Baseline of record: 1506 passed / 0 failed on this sha (dev-check.md);
qa-report.md relies on the same number; no drop (1256 before the ticket, 1506 after).
Targeted re-run: `tests/pipeline/test_install_merge.sh` at the sha, bounded to 25 min: 71 of 73 checks reached, all
ok, 0 failures; the bound expired before the last 2 checks. No process left running.
`git diff d7815e3 0991b4f -- tests/pipeline/test_guard_merge.sh tests/pipeline/test_adapters.sh` removes 0 lines (AC-24).

## Staging verification
| AC / flow | Role | Result | Evidence |
|---|---|---|---|
| releases.md Dev = QA = Staging; origin/staging = 0991b4f | devops | PASS | `git rev-parse origin/staging`; releases.md lines agree |
| AC-1 clean install allowed through the route (guard fed hook JSON, reference = worktree) | installing developer | PASS | fixture: guard exit 0 |
| AC-8 install plus an extra file blocked, file named | pipeline owner | PASS | guard exit 2, "src/Backdoor.java is not part of the install" |
| R1: the proof cannot be met by agent-settable state | pipeline owner | **FAIL** | SHI-55: `git update-ref refs/remotes/origin/master <evil>` (guard exit 0), then the same install+Backdoor commit is allowed (guard exit 0; `init.sh --verify-install` exit 0); the request against the real trunk contains src/Backdoor.java |
| AC-31..AC-42 route on fake GitHub/GitLab/Bitbucket hosts | installing developer | PASS (71/73 reached) | test_install_merge.sh at the sha |
| AC-43..AC-51 docs, version, personas | installing developer | PASS | plugin.json 3.2.0; CHANGELOG `## v3.2.0`; no "reviewed install" wording; `install-merge` absent from commands/ship.md and agents; agents/ and .claude/agents/ identical |
| AC-52 live install-and-merge; protected-trunk fallback | installing developer | NOT RUN (owner-accepted open item) | owner comment on SHI-45, 2026-09-28T10:33Z: to be checked by hand later |

## Checklist results
| Section | Item | Result | Evidence |
|---|---|---|---|
| 1 Build & tests (blocking) | run-all.sh green, count at or above baseline | PASS (of record) | 1506/0 at this sha in dev-check.md; full re-run waived by owner; targeted file 0 failures |
| 1 | Every AC maps to a passing test | PASS | qa-report.md traceability AC-1..51 |
| 1 | Dev = QA = Staging | PASS | releases.md, origin/staging |
| 1 | Every AC walked end to end from the staging ref | PARTIAL | AC-52 and fallback not run live (owner-accepted); guard cases run on fixtures |
| 2 Domain risks (blocking) | write-boundary hooks | **FAIL** | SHI-55 (guard-merge.sh install route bypass) |
| 2 | init.sh idempotency, no clobber | PASS | install-merge.sh classified as tooling (tooling loop and header list); AC-43 of record |
| 2 | gate.sh, check-signoff.sh, promote.sh, next-version.sh, allow-paths.sh, settings.json, agent frontmatter | PASS | unchanged by this ticket (`git diff d7815e3 0991b4f` empty for them) |
| 2 | cross-platform shell | PASS | no CR bytes in the changed scripts; run on Git Bash |
| 3 Security (blocking) | no secrets in the diff; placeholders only | PASS | grep over the diff: none |
| 3 | allow-paths.sh / guard-merge.sh enforce their boundaries (tested) | **FAIL** | SHI-55 |
| 3 | tracker input treated as data | PASS | intake.sh and tracker input paths untouched by this ticket |
| 4 Data & migrations (blocking) | no project-owned file overwritten; args validated first | PASS | no migration; new file is tooling; project-owned list unchanged |
| 4 | rollback approach documented | PASS | see Rollback plan |
| 5 Infrastructure & delivery | plugin installs from the staging ref; pipeline-init scaffolds | PARTIAL | init.sh from the sha scaffolds fixtures correctly; plugin install from the ref not run live (same open item as AC-52) |
| 5 | same sha on master, staging, tag | PASS so far | master contains 0991b4f; tag not cut yet |
| 5 | plugin.json version matches the proposed tag | NOTE | plugin.json 3.2.0, but next-version.sh SHI-45 proposes **v1.2.0**: the only tags are v1.0.0 and v1.1.0 (v2.0.0 to v3.1.0 were never tagged). The owner must set Version: v3.2.0 at go-live |
| 5 | previous production tag recorded | PASS | v1.1.0 (37c0ab6) |
| 6 Product & brand | product/requirements approved; no open clarifications | PASS | both Status: approved; clarifications.md empty |
| 6 | User-facing set honestly | PASS | yes; /pipeline-init behaviour changes |
| 6 | CHANGELOG one section, upgrade steps | PASS with note | v3.2.0 section plus "Upgrading from 3.1.0"; it omits SHI-30 (owner-merged PR #9: /pipeline-init signs in first and lists tracker teams), which ships in this sha too |
| 6 | installer-facing text matches behaviour | PASS | pipeline-init.md q7, step 8, Impact lines; README; both BRANCHING.md |
| 6 | personas project-agnostic | PASS | no persona or command change names install-merge |
| 7 Tickets (blocking) | eng done; defects verified | **FAIL** | SHI-47..50 Done; SHI-55 (High) open |
| 7 | tickets.md matches the tracker | PASS | children listing = mirror, plus the SHI-55 row |
| 8 Docs | README, BRANCHING, TICKETS, CLOUD; STATUS.md | PASS with note | new tooling path documented; CONTEXT.md Stack test list lacks test_install_merge.sh and test_adapters.sh (PO to update) |

## Defect tickets raised / verified
- SHI-55 (defect, Found-in: staging, High, open): the install proof takes the trunk tip from the local remote-tracking
  ref, which any agent can rewrite with an ungated git update-ref (or redirect through PIPELINE_REMOTE in the
  working-tree pipeline.env). A non-install commit then passes the guard and the route's own check and would be
  merged with no ticket. Violates product.md R1.

## Blocking items
- SHI-55 (sections 2, 3, 7).

## Open items accepted by the owner (not blocking on their own)
- AC-52 live /pipeline-init install-and-merge on a throwaway GitHub repo, and the protected-trunk fallback
  (REFUSED, then --open-only, then the fallback line): not run; the owner accepted QA without them (SHI-45 comment
  2026-09-28) and will check them by hand. They remain unverified at staging.

## Notes for the owner
- Go-live version: set v3.2.0 by hand; next-version.sh will propose v1.2.0 (tag history gap).
- The v3.2.0 tag also ships SHI-30's /pipeline-init change, which has no CHANGELOG line.
- Pre-existing, not from this ticket: 20 .sh files (including the new install-merge.sh, host.sh, tracker.sh and the
  adapters) are committed as mode 100644; the suite's -x check passes only because Git Bash reports every .sh as
  executable.
- Residual by design (FR-3 class F): scripts/pipeline/pipeline.env may carry any content in an unreviewed install
  merge, and most pipeline scripts source it. Worth reviewing alongside the SHI-55 fix.

## Rollback plan
Nothing deploys. Rollback = consumers stay on, or reinstall, the previous tag v1.1.0 (37c0ab6, the latest tag). The
v3.2.0 tag is not cut until go-live. If v3.2.0 is cut and must be withdrawn, point installs back at v1.1.0 (or the
previous master sha d7815e3) and re-run /pipeline-init.
