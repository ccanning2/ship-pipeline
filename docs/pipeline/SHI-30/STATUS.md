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
| 4 | build | senior-engineer | done | 2118b36, 1256 tests pass |
| 5 | dev | devops (merge → master, dev check) | skipped (team not selected) | |
| 6 | qa | qa-tester | skipped (team not selected) | |
| 7 | staging | app-specialist | skipped (team not selected) | |
| 8 | go-live | the owner | skipped (team not selected) | |
| 9 | production | devops (tag vX.Y.Z) | skipped (team not selected) | |

## Next action
Finished: build done on feature/SHI-30-detect-tracker-team (2118b36). Dev onwards not selected; the build is with the owner.

## Waiting on the owner
- the build on feature/SHI-30-detect-tracker-team (2118b36): review, verify, and merge or promote it yourself

## Open defect tickets
- none
