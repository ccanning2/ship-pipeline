# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | pending | |
| 3 | product | product-owner | pending | |
| 4 | analysis | business-analyst ⇄ product-owner | pending | |
| 5 | build | senior-engineer | pending | |
| 6 | dev | senior-engineer (merge → master, self-check) | pending | |
| 7 | qa | qa-tester | pending | |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Run market-researcher on SHI-5 (build-later/drop check not skipped — ticket has no Bug/Security/Chore label).

## Waiting on the owner
- nothing

## Workspace note
Ship Pipeline Linear workspace was empty of Stage/Owner labels; created the two label groups
this session. Linear rejects duplicate names across groups, so the Owner-group roles that
collided with Stage names are: `qa-tester` (not `qa`) and `the-owner` (not `owner`, which also
collides with the group's own name). Use these exact names for this workspace going forward.

## Open defect tickets
- none
