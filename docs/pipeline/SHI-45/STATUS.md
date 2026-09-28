# SHI-45 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-45/merge-prs-when-running-init
Branch: feature/SHI-45-init-merges-prs
Teams: project (analysis,engineering,devops,qa,signoff)
Arrives at: analysis
Rework loops used: 1/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | |
| 2 | product | product-owner (plan) | done | approved (feature, user-facing); follow-up SHI-46 |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | done (amended for SHI-55) | 18 FRs, 63 ACs; fix criteria on SHI-55; follow-up SHI-56; Q-1 to owner (go-live only) |
| 4 | build | senior-engineer | rework | fix SHI-55 (FR-17, FR-18, AC-53..AC-63) |
| 5 | dev | devops (merge → master, dev check) | pending re-run | previous: 1506 pass; dev+qa 0991b4f |
| 6 | qa | qa-tester | pending re-run | previous: pass, 0 defects; AC-52 + fallback not run live |
| 7 | staging | app-specialist | blocked | SHI-55 (High) raised; back to build |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Engineer fixes SHI-55 against the amended requirements.md. The route reads the trunk tip from the host before the
push and again before the merge (FR-17). It never executes pipeline.env (FR-18). The guard stays network-free. Add
AC-53..AC-63, move SHI-55 to fixed with the commit, then re-promote for re-test.

## Waiting on the owner
- Q-1 (clarifications.md): does v3.2.0 go-live wait for follow-up SHI-56 (pipeline.env)? Needed before go-live, not before the build.

## Open defect tickets
- SHI-55 (High, staging): install route trusts the local origin/master ref
