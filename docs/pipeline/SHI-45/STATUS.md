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
| 3 | analysis | business-analyst ⇄ product-owner (plan) | in-progress | |
| 4 | build | senior-engineer | pending | |
| 5 | dev | devops (merge → master, dev check) | pending | |
| 6 | qa | qa-tester | pending | |
| 7 | staging | app-specialist | pending | |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Run business-analyst on SHI-45.

## Waiting on the owner
- nothing

## Open defect tickets
- none
