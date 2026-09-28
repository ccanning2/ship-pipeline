# SHI-45 — Dev check (devops)

Result: pass
Environment: dev
Commit: 6a619f723cf90822c01d6975aaac6898c3fd265a

Rework loop 1 (SHI-55 fixed, SHI-57 built, commit d50b581). Dev is the `master` ref (PIPELINE_HAS_DEPLOY_ENVS=no: no deploy, health or smoke step). Checked in a clean worktree at the Dev sha.

| Check | Result | Notes |
|---|---|---|
| Merge to master via promote.sh (gate PASS) | pass | Fast-forward to 6a619f7; master tip 101a8c5 adds only the release record |
| `bash tests/pipeline/run-all.sh` on the Dev sha | pass | ALL PIPELINE TESTS PASSED: 1930 passed, 0 failed (test_install_merge.sh 390, test_guard_merge.sh included) |
| `.claude-plugin/plugin.json` version | pass | 3.2.0 |
| CHANGELOG.md has a v3.2.0 section | pass | `## v3.2.0` present |
| SHI-55 repro on a fixture (forged `refs/remotes/origin/master` -> evil, route run directly with the fake host), GitHub, GitLab and Bitbucket fakes | pass | Each: `NOT-INSTALL src/Backdoor.java: src/Backdoor.java is not part of the install`, exit 4; the only host call is the trunk-head read; nothing pushed, no request opened; the trunk is unchanged |
| `touch <file>` appended to the working-tree pipeline.env, route run | pass | The file was never created (pipeline.env read as data) |
| CI / deploy / infra changes from impl-notes (For devops) | n/a | none listed; no changes to CI files, scripts/deploy or run-all.sh between 0991b4f and 6a619f7 |

Not checked here (QA): the manual AC-52 install on a throwaway GitHub repo and the protected-trunk fallback (the owner earlier accepted these live runs as open), the guard-by-hand cases, and the committed `FOO="x"` FR-19 guard block (covered by the suite, AC-64..AC-74).
