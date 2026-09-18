# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | done | Recommendation: build (both halves together) |
| 3 | product | product-owner | done | approved · feature · User-facing: yes · P2 · 9 stories → SHI-7/8/9, follow-ups SHI-10/11/12 |
| 4 | analysis | business-analyst ⇄ product-owner | done | requirements.md approved · 34 FRs / 38 ACs · 8 eng tickets SHI-13..SHI-20 |
| 5 | build | senior-engineer | pending | |
| 6 | dev | senior-engineer (merge → master, self-check) | pending | |
| 7 | qa | qa-tester | pending | |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Run senior-engineer (mode build) on SHI-5. Work the eng tickets in dependency order:

```
SHI-13 (config keys + fail-closed resolution)   ← start here, unblocked
   ├─► SHI-14 (gate.sh production condition)    ← BLOCKED on owner approval of requirements.md §4
   │      └─► SHI-15 (backwards-compat proof)   ← release blocker (BR-5)
   ├─► SHI-16 (promote.sh: no deploy/smoke)
   ├─► SHI-17 (init.sh / pipeline-init scaffolding)
   └─► SHI-18 (ship.md, personas, status.sh)
SHI-14 + SHI-16 + SHI-17 ─► SHI-19 (docs + v1.1.0)
SHI-14 + SHI-16 ─────────► SHI-20 (dogfood this repo)  ← LAST, must land before stage 6 (dev)
```

## Waiting on the owner
- nothing currently open.

Closed:
- Q-1 answered 2026-09-18 — SHI-5 runs under the new rules; this repo's marketing capability is
  flipped off during the build (SHI-20), before stage 6.
- Q-2 answered 2026-09-18 — process answer only ("bring the specific list back"); the list is now in
  requirements.md §4 and the approval itself was Q-3.
- Q-3 answered 2026-09-18 — **approved as written**. `gate.sh`'s production-stage marketing
  requirement gains one conjunct (`&& [ "$has_marketing" = yes ]`); nothing else in `gate.sh` changes.
  SHI-14 (and downstream SHI-15/19/20) unblocked.

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
