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
| 7 | staging | the owner (team not selected) | done | owner signed off 1281f18 on staging (signoff.md) |
| 8 | go-live | the owner | done | go: v3.3.0 on 1281f18 (approved 2026-09-30T07:25:10Z) |
| 9 | production | devops (tag vX.Y.Z) | done | v3.3.0 tagged on 1281f18; plugin.json 3.3.0 |

## Next action
None. Shipped as v3.3.0 on 1281f18.

## Waiting on the owner
- nothing

## Open defect tickets
- none
