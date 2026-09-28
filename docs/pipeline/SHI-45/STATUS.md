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
| 5 | dev | devops (merge → master, dev check) | in-progress | previous: 1506 pass; dev+qa 0991b4f |
| 6 | qa | qa-tester | pending re-run | previous: pass, 0 defects; AC-52 + fallback not run live |
| 7 | staging | app-specialist | blocked | SHI-55 (High) raised; back to build |
| 8 | go-live | the owner | pending | waits for SHI-55 and SHI-57 (Q-1 (a)) |
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
- nothing (Q-1 answered: (a) narrow pipeline.env fix before go-live; PO confirmed it as R1c-2)

## Open defect tickets
- SHI-55 (High, staging): install route trusts the local origin/master ref
