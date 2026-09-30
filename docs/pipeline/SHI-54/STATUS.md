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
| 5 | dev | devops (merge → master, dev check) | done | dev check pass @ 1281f18; promoted to qa |
| 6 | qa | the owner (team not selected) | done | owner approved 1281f18 on qa (qa-report.md) |
| 7 | staging | the owner (team not selected) | in-progress | promoted 1281f18 to staging; waiting on the owner's sign-off |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
Stage 7 staging: owner signs off 1281f18 on the staging ref; then
`bash scripts/pipeline/handover.sh SHI-54 --by-owner signoff`.

## Waiting on the owner
- Staging sign-off of 1281f18 (signoff team not selected; sign-off is the owner's, never devops')

## Open defect tickets
- none
