# SHI-45 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-45/merge-prs-when-running-init
Branch: feature/SHI-45-init-merges-prs
Teams: project (analysis,engineering,devops,qa,signoff)
Arrives at: analysis
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | |
| 2 | product | product-owner (plan) | done | approved (feature, user-facing); follow-up SHI-46 |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | done | 16 FRs, 52 ACs; eng SHI-47..SHI-50 |
| 4 | build | senior-engineer | done | 1506 tests pass; 73d98fe |
| 5 | dev | devops (merge → master, dev check) | done | 1506 pass; dev+qa 0991b4f |
| 6 | qa | qa-tester | pending | |
| 7 | staging | app-specialist | pending | |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Run qa-tester on the build on qa (0991b4f).

## Waiting on the owner
- nothing

## Open defect tickets
- none
