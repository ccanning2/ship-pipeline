# SHI-45 — Dev check (devops)

Result: pass
Environment: dev
Commit: 0991b4ff2f1a6f85bc1a48b673e7b895c8f011e9

Dev is the `master` ref (PIPELINE_HAS_DEPLOY_ENVS=no: no deploy, health or smoke step). Checked in a clean worktree at the Dev sha.

| Check | Result | Notes |
|---|---|---|
| Merge to master via promote.sh (gate PASS) | pass | Fast-forward; master tip 4ae1596 adds only the release record |
| `bash tests/pipeline/run-all.sh` on the Dev sha | pass | ALL PIPELINE TESTS PASSED: 1506 passed, 0 failed, including test_install_merge.sh and test_guard_merge.sh |
| `.claude-plugin/plugin.json` version | pass | 3.2.0 |
| CHANGELOG.md has a v3.2.0 section | pass | `## v3.2.0` present |
| CI / deploy / infra changes from impl-notes (For devops) | n/a | none listed |

Not checked here (QA, per impl-notes): the manual AC-52 install on a throwaway GitHub repo, the protected-trunk fallback, and the guard-by-hand cases.

Re-entry at dev: the first push of e1e294d to `staging` was rejected (non-fast-forward) because `staging` held a GitHub merge commit (268c754, PR #8, whose content equals master 6065077). `origin/staging` was merged into the ticket branch (no content change) and re-promoted; the new Dev sha 0991b4f differs from the tested e1e294d only in docs/pipeline/SHI-45 records (releases.md, deploy-history.md, dev-check.md), so the results above stand for it.
