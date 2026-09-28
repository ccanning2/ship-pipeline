# SHI-45 — Staging sign-off

Decision: approved
Environment: staging
Commit: 6a619f723cf90822c01d6975aaac6898c3fd265a
Signed: 2026-09-28

Rework loop 1 re-check. Staging is the `staging` ref at the sha above (PIPELINE_HAS_DEPLOY_ENVS=no; the artefact is
plugin v3.2.0). Checked in a clean detached worktree at that sha in the session scratchpad, against the amended
requirements.md (19 FRs, 76 ACs) and product.md (R1-R8, including R1c-2). Nothing was pushed to any host; no repo or PR
created; local fixtures and the suite's fake hosts only. Previous sign-off (0991b4f): blocked by SHI-55.

## Test re-run
Suite: full `run-all.sh` not re-run (owner constraint: 45+ min here). Baseline of record: 1930 passed / 0 failed on
this sha (dev-check.md); qa-report.md relies on the same run. No drop: 1506 at 0991b4f, 1930 now.
Targeted re-run by the app specialist: `tests/pipeline/test_guard_merge.sh` at the sha: **298 passed, 0 failed**
(matches qa-report.md and impl-notes.md). `test_install_merge.sh` (390 per QA) not re-run; replaced by the independent
repros below. All processes finished before sign-off.
`git diff 0991b4f 6a619f7` is empty for guard-merge.sh, allow-paths.sh, the other hooks, gate.sh, check-signoff.sh,
promote.sh, next-version.sh, both settings.json and every agent file.

## Staging verification
| AC / flow | Role | Result | Evidence |
|---|---|---|---|
| releases.md Dev = QA = Staging = 6a619f7; origin/staging = 6a619f7 | devops | PASS | `git rev-parse origin/staging`; releases.md |
| SHI-55 original repro (forged `refs/remotes/origin/master` -> evil), GitHub, GitLab, Bitbucket fakes (AC-53, AC-54) | pipeline owner | PASS | guard pre-check exit 0 (by design, FR-5d); route direct exit 4 `NOT-INSTALL src/Backdoor.java`; only the trunk-head read reached the host; nothing pushed; trunk unchanged; all three hosts |
| Same, plus forged `refs/heads/master` and `FETCH_HEAD` | pipeline owner | PASS | exit 4, no push, all three hosts |
| PIPELINE_REMOTE variant: `fork` in both pipeline.env copies, fork master = evil (AC-55) | pipeline owner | PASS | exit 4, nothing pushed to fork or origin, all three hosts |
| Working-tree pipeline.env holds liar PIPELINE_GH/GLAB/CURL_CMD and a `touch` line (AC-59, FR-18) | pipeline owner | PASS | exit 4 through the honest fake; marker never created; all three hosts |
| Own probe: host install branch pre-seeded with install+backdoor, `remote.origin.pushurl` redirected so the route's push lands elsewhere | pipeline owner | PASS | exit 3 `REFUSED ... source commit is <E>, not the install commit`; 0 merge calls; trunk unchanged |
| Guard route form: inline `PIPELINE_PLUGIN_ROOT=`, a second command, an extra argument (FR-5b, FR-5e) | pipeline owner | PASS | guard exit 2 in each case |
| Positive control: clean install on the real trunk (AC-1, AC-31) | installing developer | PASS | guard exit 0; route `MERGED`; trunk = install commit |
| SHI-57 / FR-19 content rule: 40 committed-pipeline.env cases through the reference verifier (`init.sh --verify-install --trunk-tip`), each file also sourced with bash | pipeline owner | PASS | Every line bash would execute fails: `;`, `&&`, a command after a tab or space, a command on an unterminated last line, a CR mid-line, `#` inside quotes. These also fail: export, readonly, declare, alias, `+=`, arrays, globs, braces, tilde, backslash, unicode quotes, a BOM, unknown keys (PATH, BASH_ENV) and duplicates. These pass, and none runs anything when sourced: the rendered file, a CRLF file, a single-quoted command substitution, trailing comments, an empty value, the allowed bare punctuation. Reasons name the line and key, never the value |
| AC-63, AC-75: docs sentences | installing developer | PASS | both BRANCHING.md copies and CHANGELOG v3.2.0 carry the host-anchored sentence and the pipeline.env "nothing but comments and plain settings from the plugin's template ... falls back to the owner" sentence; known limits name SHI-56 |
| AC-76: CONTEXT.md Tests bullet | plugin author | PASS | all 11 files in the run-all.sh tests list are named |
| AC-43..AC-51 docs, version, personas | installing developer | PASS | plugin.json 3.2.0; agents/ = .claude/agents/; `install-merge` absent from commands/ship.md and agents; "not opened" Impact line in pipeline-init.md; no "reviewed install" wording |
| AC-52 live install-and-merge; protected-trunk fallback | installing developer | NOT RUN (owner-accepted open item) | owner comment on SHI-45, 2026-09-28T10:33Z |

## Checklist results
| Section | Item | Result | Evidence |
|---|---|---|---|
| 1 Build & tests (blocking) | run-all.sh green, count at or above baseline | PASS (of record) | 1930/0 at this sha (dev-check.md); full re-run waived by owner; test_guard_merge.sh 298/0 re-run here |
| 1 | Every AC maps to a passing test | PASS | qa-report.md traceability AC-1..AC-76 |
| 1 | Dev = QA = Staging | PASS | releases.md, origin/staging |
| 1 | Every AC walked end to end from the staging ref | PARTIAL (owner-accepted) | AC-52 and the fallback not run live; all other flows run on fixtures from the sha |
| 2 Domain risks (blocking) | write-boundary hooks | PASS | SHI-55 closed on all three hosts (above); guard-merge.sh and allow-paths.sh unchanged; 298/0 |
| 2 | init.sh idempotency, no clobber, args validated first | PASS | re-run over edited CONTEXT.md, RELEASE_CHECKLIST.md, pipeline.env, settings.json, pipeline-gate.yml: all byte-identical; `--bogus` exits 1 and writes 0 files; the install path (copy_owned) is unchanged apart from the --list class |
| 2 | gate.sh, check-signoff.sh, promote.sh, next-version.sh, agent frontmatter | PASS | unchanged since 0991b4f |
| 2 | cross-platform shell | PASS | no CR bytes in the changed scripts; a CRLF pipeline.env is accepted by FR-19; run on Git Bash |
| 3 Security (blocking) | no secrets in the diff; placeholders only | PASS | grep over the rework diff: none |
| 3 | allow-paths.sh / guard-merge.sh enforce their boundaries (tested) | PASS | test_guard_merge.sh 298/0; route-form probes blocked |
| 3 | tracker input treated as data | PASS | intake.sh and tracker paths untouched by the rework |
| 4 Data & migrations (blocking) | no project-owned file overwritten; args validated first | PASS | as in section 2 |
| 4 | rollback approach documented | PASS | see Rollback plan |
| 5 Infrastructure & delivery | plugin installs from the staging ref; pipeline-init scaffolds | PARTIAL | init.sh from the sha scaffolds fixtures correctly; live `/plugin install` from the ref not run (same open item as AC-52) |
| 5 | same sha on master, staging, tag | PASS so far | master contains 6a619f7; tag not cut yet |
| 5 | plugin.json version matches the proposed tag | NOTE | plugin.json 3.2.0; `next-version.sh SHI-45` still proposes v1.2.0 (the only tags are v1.0.0 and v1.1.0). The owner must record Version: v3.2.0 at go-live |
| 5 | previous production tag recorded | PASS | v1.1.0 (37c0ab6) |
| 6 Product & brand | product/requirements approved; no open clarifications | PASS | Q-1 answered (a); R1c-2 confirmed by PO |
| 6 | User-facing set honestly | PASS | yes; /pipeline-init behaviour changes |
| 6 | CHANGELOG one section, upgrade steps | PASS with note | v3.2.0 section plus "Upgrading from 3.1.0"; still no line for SHI-30 (PR #9), which ships in this tag |
| 6 | installer-facing text matches behaviour | PASS | CHANGELOG SHI-55 / SHI-57 bullets and known limits match what the route does |
| 6 | personas project-agnostic | PASS | agents unchanged; the two copies are identical |
| 7 Tickets (blocking) | eng done; defects verified | PASS | SHI-47..50 and SHI-57 Done; SHI-55 verified (re-verified here); no wontfix |
| 7 | tickets.md matches the tracker | PASS | `tracker.sh children SHI-45` = mirror (verified maps to Done in tracker.map) |
| 8 Docs | README, BRANCHING, TICKETS, CLOUD; STATUS.md | PASS | new host.sh verb `branch-head` documented in host-common.sh and CHANGELOG; CONTEXT.md test list now complete |

## Defect tickets raised / verified
- SHI-55 (defect, Found-in: staging, High): re-verified by the app specialist on 6a619f7 with the original repro, the
  PIPELINE_REMOTE variant and a pushurl variant, on all three host fakes. It stays verified.
- No new defects.

## Earlier notes re-examined (none is a blocker)
- pipeline.env: R1c-2 / SHI-57 closes the unreviewed-install part (verified above). What remains is follow-up SHI-56:
  the scripts, the guard for other commands and CI still `source` the file. The v3.2.0 known limits say so.
- next-version.sh proposes v1.2.0. Section 5 is not blocking, and promote.sh tags whatever Version the owner records.
  The owner must record v3.2.0.
- Executable bit: 20 `.sh` files are mode 100644 in the index, the same count as at 0991b4f, and the new
  install-merge.sh is one of them. Consumers are not affected: init.sh runs `chmod +x` on scripts/pipeline/*.sh and
  the hooks, and every hook and script is called with `bash`. However, the suite's `-x` check (test_config.sh) passes
  only on Git Bash, and the files break the CONTEXT.md rule "keep every scripts/**/*.sh executable". Recommend the PO
  file a follow-up (`git update-index --chmod=+x`).
- SHI-30 is missing from the CHANGELOG. Section 6 is not blocking. The owner may add one line before tagging.

## Residual risks for the owner (by design, not defects)
- Bitbucket: its merge call takes no sha. The route re-reads the source commit just before merging (FR-7.5). The guard
  lets ticketless pushes, including force pushes, reach `ship-pipeline/install` like any non-trunk branch (checked:
  exit 0). So an agent that deliberately races a push into that window could get another commit merged. This falls
  within the stated known limit that the guard sees tool calls only. A future guard rule that reserves the install
  branch for the route would close it on every host. The PO may want it alongside SHI-46 and SHI-56.
- By design, the guard's own pre-check still trusts the local trunk ref (FR-5d). The route's host-anchored check makes
  the decision, and it does so from the owner's terminal too.
- CONTEXT.md and RELEASE_CHECKLIST.md stay free content in an unreviewed install (R1c, owner decision). Every persona
  reads them.

## Open items accepted by the owner (not blocking on their own)
- Not run: the AC-52 live /pipeline-init install-and-merge on a throwaway GitHub repo, and the protected-trunk
  fallback (REFUSED, then --open-only, then the fallback line). The owner accepted checking them by hand (SHI-45
  comment 2026-09-28T10:33Z). They remain unverified at staging, as does a live `/plugin install` from the staging ref.

## Rollback plan
Nothing deploys. To roll back, consumers stay on, or reinstall, the previous tag v1.1.0 (37c0ab6, the latest tag).
The v3.2.0 tag is cut only at go-live. If it must be withdrawn, point installs back at v1.1.0 (or master d7815e3,
before this ticket) and re-run /pipeline-init. install-merge.sh does nothing when "Branches" is unticked.
