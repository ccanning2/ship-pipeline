# SHI-45 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-45/merge-prs-when-running-init
Branch: feature/SHI-45-init-merges-prs
Teams: project (analysis,engineering,devops,qa,signoff)
Arrives at: analysis
Rework loops used: 1/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | |
| 2 | product | product-owner (plan) | done | approved (feature, user-facing); follow-up SHI-46; R1c-2 + US-7 added (Q-1) |
| 3 | analysis | business-analyst ⇄ product-owner (plan) | done (amended for SHI-55 and R1c-2) | 19 FRs, 76 ACs; fix criteria on SHI-55; FR-19 + AC-64..AC-76 for R1c-2 (SHI-57); follow-up SHI-56; Q-1 answered (a) |
| 4 | build | senior-engineer | done (rework 1) | 1930 pass; d50b581 |
| 5 | dev | devops (merge → master, dev check) | done (rework 1) | 1930 pass; dev+qa 6a619f7 |
| 6 | qa | qa-tester | done (rework 1) | pass on 6a619f7; SHI-55 verified; AC-52 + fallback not run live (owner-accepted) |
| 7 | staging | app-specialist | done (rework 1) | approved on 6a619f7; SHI-55 re-verified |
| 8 | go-live | the owner | waiting on the owner | waits for SHI-55 and SHI-57 (Q-1 (a)) |
| 9 | production | devops (tag vX.Y.Z) | pending | |

## Next action
The engineer fixes SHI-55 and builds SHI-57 against the amended requirements.md, on the ticket branch.
- **SHI-55.** The route reads the trunk tip from the host before the push and again before the merge (FR-17). It
  never executes pipeline.env (FR-18). The guard stays network-free.
- **SHI-57.** A changed `pipeline.env` in the install diff may hold only comments, blank lines and plain settings of the
  template's keys (FR-19). The rule applies in the guard and in the route. Update the `Tests:` bullet of CONTEXT.md
  (AC-76).
- **Then.** Move both tickets to fixed with the commit, and hand to devops to re-promote for re-test.

## Waiting on the owner
- Go-live decision: release v3.2.0 (sha 6a619f7) to production?

## Open defect tickets
- none (SHI-55 verified)
