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
| 5 | build | senior-engineer | done | all 8 eng tickets Done · 613 passed / 0 failed (master baseline 419 / 4) · gate.sh dev: PASS |
| 6 | dev | senior-engineer (merge → master, self-check) | done | Dev = QA = 2e9552d · self-check pass (throwaway-repo install from the ref) · suite 613 / 0 |
| 7 | qa | qa-tester | in progress | staging branch = 2e9552d |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
qa-tester verifies requirements.md's ACs against the staging ref (no host: install from the ref and run
the flow). Defects come back as `defect` tickets to the engineer, then re-enter at dev. On pass, run
promote-staging (`promote.sh SHI-5 staging`, a no-op dispatch here) and hand to the app-specialist.
Marketing is skipped for this ticket by configuration (PIPELINE_HAS_MARKETING=no).

## Waiting on the owner
- Nothing blocking. Two things to decide by go-live (also in impl-notes.md, Known limitations):
  1. Version: `next-version.sh` will propose `v0.1.0` because this repo has no git tags. Tag the released
     v1.0.0 first, or answer "go as v1.1.0". `plugin.json` is already 1.1.0.
  2. `plugin.json` has no `commands`/`agents` keys; the build agent weakened `test_config.sh`'s
     assertion to match. Confirm that is intended.
  Follow-up candidate: this repo's `.github/workflows/deploy.yml` will fail on pushes/tags (no Dockerfile).

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
