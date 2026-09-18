# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 0/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | done | Recommendation: build (both halves together) |
| 3 | product | product-owner | pending | |
| 4 | analysis | business-analyst ⇄ product-owner | pending | |
| 5 | build | senior-engineer | pending | |
| 6 | dev | senior-engineer (merge → master, self-check) | pending | |
| 7 | qa | qa-tester | pending | |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Run product-owner (mode A) on SHI-5 to scope the requirement, per research.md's three carry-forward
points (split project-capability from per-ticket User-facing; one pipeline with capability flags,
not a forked shape; pipeline.env never updates existing installs in place, so new flags must default
to current behaviour). Paused pending the owner's direction on the two process findings below.

## Waiting on the owner
- Two findings surfaced during research, outside SHI-5's own scope — see Linear comment 4f8d7059:
  1. `scripts/pipeline/hooks/allow-paths.sh` cannot match a Windows backslash path (`case "$path" in
     "$project"/*)` requires a literal `/`), so every allow-glob misses on Windows and a legitimate,
     permitted write gets blocked. The market-researcher subagent hit this live, disclosed it, and
     worked around it via the shell rather than dead-ending — meaning persona write boundaries are
     currently not enforced at all on Windows/Git-Bash for any tool the hook's `Edit|Write|MultiEdit`
     matcher doesn't cover. Named a write-boundary hook in CONTEXT.md — fixing it is a "stop and ask
     first" item per the engineering rules.
  2. `docs/pipeline/_templates/research.md` carries leftover domain-specific placeholders from an
     unrelated product (wedding-vendor marketplace) and ships to every consumer via `init.sh`.

## Workspace note
Ship Pipeline Linear workspace was empty of Stage/Owner labels; created the two label groups
this session. Linear rejects duplicate names across groups, so the Owner-group roles that
collided with Stage names are: `qa-tester` (not `qa`) and `the-owner` (not `owner`, which also
collides with the group's own name). Use these exact names for this workspace going forward.

## Open defect tickets
- none
