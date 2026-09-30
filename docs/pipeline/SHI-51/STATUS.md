# SHI-51 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-51/minimise-the-mrpr-requirement-gate
Branch: feature/SHI-51-minimise-human-gates
Teams: project (analysis,engineering,devops,qa,signoff)
Arrives at: analysis
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | |
| 2 | product | product-owner (plan) | in-progress | |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | pending | |
| 4 | build | senior-engineer | pending | |
| 5 | dev | devops (merge → master, dev check) | pending | |
| 6 | qa | qa-tester | pending | |
| 7 | staging | app-specialist | pending | |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Run product-owner (mode A) on SHI-51.

## Waiting on the owner
- nothing

## Open defect tickets
- none
