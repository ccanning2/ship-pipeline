# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | done | Recommendation: build (both halves together) |
| 3 | product | product-owner | done | approved · feature · User-facing: yes · P2 · 9 stories → SHI-7/8/9, follow-ups SHI-10/11/12 |
| 4 | analysis | business-analyst ⇄ product-owner | pending | |
| 5 | build | senior-engineer | pending | |
| 6 | dev | senior-engineer (merge → master, self-check) | pending | |
| 7 | qa | qa-tester | pending | |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Run business-analyst on SHI-5: write `requirements.md` and create the `eng` tickets from the three
story tickets. Carry through the three points in the product-owner handoff comment — name the exact
`gate.sh` before/after conditions (so the owner approves a specific diff, Q-2), make backwards
compatibility for existing installs a release-blocking acceptance criterion (BR-5), and keep every
capability fail-closed (BR-8).

## Waiting on the owner
Two open `To: Owner` questions in `clarifications.md`. Neither blocks the analysis stage; both must
be answered before stage 5 (build).
- **Q-1** — SHI-5 is `User-facing: yes`, so today its own production gate requires a completed
  `marketing` ticket. Switching this repo onto the new settings during the build (BR-15) turns its
  marketing capability off with immediate effect, including for SHI-5's own remaining stages. Should
  SHI-5 finish under the old rules or the new ones? PO recommendation: the new ones.
- **Q-2** — CONTEXT.md requires a stop-and-ask before `gate.sh`'s pass/fail conditions change, and
  this work changes them. PO recommendation: approve the specific before/after list once the BA has
  written it into `requirements.md`, rather than granting blanket permission now.

Previously raised, now closed:
- `scripts/pipeline/hooks/allow-paths.sh` Windows backslash path bug — **fixed and verified** in
  d4f9b21.
- `docs/pipeline/_templates/research.md` placeholder text from an unrelated product — tracked as
  **SHI-10** (follow-up, out of scope for SHI-5).

## Workspace note
Ship Pipeline Linear workspace was empty of Stage/Owner labels; created the two label groups
this session. Linear rejects duplicate names across groups, so the Owner-group roles that
collided with Stage names are: `qa-tester` (not `qa`) and `the-owner` (not `owner`, which also
collides with the group's own name). Use these exact names for this workspace going forward.
There is no `Kind` label group in this workspace: a child ticket's kind is recorded in its
description and in `tickets.md`, which is what the gates read.

## Open defect tickets
- none
