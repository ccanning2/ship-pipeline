# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 2/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | done | Recommendation: build (both halves together) |
| 3 | product | product-owner | done | approved · feature · User-facing: yes · P2 · 9 stories → SHI-7/8/9, follow-ups SHI-10/11/12 |
| 4 | analysis | business-analyst ⇄ product-owner | done | requirements.md approved · 34 FRs / 38 ACs · 8 eng tickets SHI-13..SHI-20 |
| 5 | build | senior-engineer | done | all 8 eng tickets Done · 613 passed / 0 failed (master baseline 419 / 4) · gate.sh dev: PASS |
| 6 | dev | senior-engineer (merge → master, self-check) | done (re-entered, loop 2/3) | Dev = QA = f9cc6af · self-check pass on the promoted ref · 49-form differential vs gate.sh |
| 7 | qa | qa-tester | done — PASS (round 3, scoped) | f9cc6af: test_init 137/0, test_config 162/0, 213-form differential, SHI-25 verified; last full suite 711/711 on 6a0cbbc; 0 defects open |
| 8 | staging | app-specialist (+ marketing skipped by configuration) | done — APPROVED | f9cc6af: full suite 728/728 (one run), all ACs walked as the three roles, RELEASE_CHECKLIST.md all blocking sections PASS, 0 defects |
| 9 | go-live | the owner | waiting on the owner | version to be set by the owner's explicit answer ("go as v1.0.0", Q-4); next-version.sh proposes v0.1.0 |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Owner answers the go-live question (go / no-go / "go as v1.0.0"). On go: write `Version:` and `Go-live: approved by <owner> <ISO time>` to
releases.md, comment the same on SHI-5, then `promote.sh SHI-5 production` tags the version on f9cc6af. Nothing is written to
releases.md before an explicit go.

## Waiting on the owner
- Nothing blocking. By go-live:
  1. Version — **decided, Q-4 (2026-09-19): this build is released as v1.0.0.** At go-live the owner must
     still answer "go as v1.0.0", because `next-version.sh` will keep proposing `v0.1.0` (0 tags, local and
     remote). SHI-24 returns `plugin.json` to 1.0.0 and folds the README notes into one v1.0.0 section.
     Owner clarification 2026-09-19: nobody is using the released 1.0.0 yet, so the version has no consumer
     impact for now (the earlier worry that installed 1.0.0 users would not be offered this build is moot);
     the version only needs to read 1.0.0 once all changes are done.
  2. Follow-up candidates the QA report found outside SHI-5's scope (owner decides whether to ticket them):
     - allow-paths.sh does not normalise `..`, so `tests/../src/x` matches `tests/*` (persona write boundary).
     - This repo's deploy.yml fires on pushes/tags and builds an image this project lacks.
     - tests/pipeline/lib.sh uses `sed -i -E` (fails on macOS BSD sed); empty `${kept[@]}` under set -u on bash < 4.4.
     - Stale text: README says "425 tests"; init.sh's closing Next-step 3 still tells an opted-out project to
       create GitHub environments; docs/pipeline/README.md mentions scripts/deploy/rollback.sh.
  Resolved: the `plugin.json` missing `commands`/`agents` keys were removed by the owner's own commit c0102d3,
  so test_config.sh's weakened assertion matches the manifest as committed.

Closed:
- Q-1 answered 2026-09-18 — SHI-5 runs under the new rules; this repo's marketing capability is
  flipped off during the build (SHI-20), before stage 6.
- Q-2 answered 2026-09-18 — process answer only ("bring the specific list back"); the list is now in
  requirements.md §4 and the approval itself was Q-3.
- Q-3 answered 2026-09-18 — **approved as written**. `gate.sh`'s production-stage marketing
  requirement gains one conjunct (`&& [ "$has_marketing" = yes ]`); nothing else in `gate.sh` changes.
  SHI-14 (and downstream SHI-15/19/20) unblocked.
- Q-4 answered 2026-09-19 — **release this build as v1.0.0**, not v1.1.0. requirements.md amended in
  place (Amendment note, FR-30, AC-35, §8 Version, §8 Rollback); supersedes BR-10's minor bump for this
  release only; product.md untouched. Raised as SHI-24 (eng, open), which amends SHI-19 (left Done).

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
