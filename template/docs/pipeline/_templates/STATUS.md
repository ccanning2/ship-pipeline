# <TICKET> — Pipeline status

Tracker: <ticket url>
Branch: <branch>
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | pending | |
| 2 | research | market-researcher | pending | |
| 3 | product | product-owner | pending | |
| 4 | analysis | business-analyst ⇄ product-owner | pending | |
| 5 | build | senior-engineer | pending | |
| 6 | dev | senior-engineer (merge → __BASE_BRANCH__, self-check) | pending | |
| 7 | qa | qa-tester | pending | |
| 8 | staging | app-specialist (+ marketing-specialist when the project has a marketing function and the ticket is user-facing; otherwise skipped by configuration) | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
<exact next step to resume from>

## Waiting on the owner
- nothing

## Open defect tickets
- none
