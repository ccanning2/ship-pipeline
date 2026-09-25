# <TICKET> — Pipeline status

Tracker: <ticket url>
Branch: <branch>
Teams: project (<the teams: scripts/pipeline/teams.sh; "project" follows pipeline.env, a list is this ticket's own choice>)
Arrives at: <analysis|engineering|devops|qa: the first selected team, or qa when the build is already on qa>
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | pending | |
| 2 | product | product-owner (plan) | pending | |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | pending | |
| 4 | build | senior-engineer | pending | |
| 5 | dev | devops (merge → master, dev check) | pending | |
| 6 | qa | qa-tester | pending | |
| 7 | staging | app-specialist | pending | |
| 8 | go-live | the owner | pending | |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
<exact next step to resume from>

## Waiting on the owner
- nothing

## Open defect tickets
- none
