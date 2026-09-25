# SHI-30 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-30/pipeline-init-detect-the-tracker-team-or-project-after-sign-in
Branch: feature/SHI-30-detect-tracker-team
Teams: engineering (this ticket)
Arrives at: engineering
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | |
| 2 | product | product-owner (plan) | skipped (upstream) | |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | skipped (upstream) | |
| 4 | build | senior-engineer | in-progress | |
| 5 | dev | devops (merge → master, dev check) | skipped (team not selected) | |
| 6 | qa | qa-tester | skipped (team not selected) | |
| 7 | staging | app-specialist | skipped (team not selected) | |
| 8 | go-live | the owner | skipped (team not selected) | |
| 9 | production | devops (tag vX.Y.Z) | skipped (team not selected) | |

## Next action
Build: senior-engineer works SHI-30 itself (engineering only, this ticket), then the build on the ticket branch goes to the owner.

## Waiting on the owner
- nothing

## Open defect tickets
- none
