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
| 5 | dev | devops (merge → master, dev check) | done outside the pipeline | merged in PR #9 (d7815e3), released in v3.2.0 |
| 6 | qa | qa-tester | done outside the pipeline | merged in PR #9 (d7815e3), released in v3.2.0 |
| 7 | staging | app-specialist | done outside the pipeline | merged in PR #9 (d7815e3), released in v3.2.0 |
| 8 | go-live | the owner | done outside the pipeline | merged in PR #9 (d7815e3), released in v3.2.0 |
| 9 | production | devops (tag vX.Y.Z) | done outside the pipeline | merged in PR #9 (d7815e3), released in v3.2.0 |

## Next action
Finished: shipped outside the pipeline. The owner merged PR #9 (d7815e3) on 2026-09-25, and it went to production in v3.2.0 with SHI-45. The owner confirmed on 2026-09-29.

## Waiting on the owner
- nothing

## Open defect tickets
- none
