# SHI-54 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-54/improve-performance
Branch: feature/SHI-54-improve-performance
Teams: engineering,devops (this ticket)
Arrives at: engineering
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | teams engineering,devops; arrives at engineering |
| 2 | product | product-owner (plan) | skipped (upstream) | |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | skipped (upstream) | |
| 4 | build | senior-engineer | done | ready-for-dev @ abecd35 |
| 5 | dev | devops (merge → master, dev check) | in-progress | |
| 6 | qa | the owner (team not selected) | pending | |
| 7 | staging | the owner (team not selected) | pending | |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Stage 5 dev: devops promote-dev.

## Waiting on the owner
- nothing

## Open defect tickets
- none
