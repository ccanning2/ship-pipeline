# SHI-5 — Pipeline status

Tracker: https://linear.app/ship-pipeline/issue/SHI-5/change-the-workflow-in-terms-of-the-persona-usage
Branch: feature/SHI-5-change-workflow-persona-usage
Rework loops used: 1/3

| # | Stage | Owner | State | Outcome |
|---|---|---|---|---|
| 1 | intake | orchestrator | done | brief written, branch created |
| 2 | research | market-researcher | done | Recommendation: build (both halves together) |
| 3 | product | product-owner | done | approved · feature · User-facing: yes · P2 · 9 stories → SHI-7/8/9, follow-ups SHI-10/11/12 |
| 4 | analysis | business-analyst ⇄ product-owner | done | requirements.md approved · 34 FRs / 38 ACs · 8 eng tickets SHI-13..SHI-20 |
| 5 | build | senior-engineer | done | all 8 eng tickets Done · 613 passed / 0 failed (master baseline 419 / 4) · gate.sh dev: PASS |
| 6 | dev | senior-engineer (merge → master, self-check) | done | Dev = QA = 2e9552d · self-check pass (throwaway-repo install from the ref) · suite 613 / 0 |
| 7 | qa | qa-tester | done — FAIL | 613/613 on 2e9552d, 38/38 ACs covered, 88-comparison differential vs v1.0.0 gate.sh = 0 diffs · 3 defects: SHI-21 (Medium), SHI-22, SHI-23 (Low) |
| 8 | staging | app-specialist + marketing-specialist | pending | |
| 9 | go-live | the owner | pending | |
| 10 | production | senior-engineer (tag vX.Y.Z) | pending | |

## Next action
Rework loop 1/3. senior-engineer fixes SHI-21, SHI-22, SHI-23 **and SHI-24** (the v1.0.0 version
decision — plugin.json, README release notes, the AC-35 test) together on the ticket branch, all
before re-promoting to dev so QA tests the final content once (QA's four
regression tests in tests/pipeline/* turn green), comments the fixing commit on each, then re-enters at
dev: `promote.sh SHI-5 dev` -> dev-check -> `promote.sh SHI-5 qa` -> qa-tester re-tests and marks each
defect verified/reopened -> promote-staging -> app-specialist. Marketing is skipped by configuration.

## Waiting on the owner
- Nothing blocking. By go-live:
  1. Version — **decided, Q-4 (2026-09-19): this build is released as v1.0.0.** At go-live the owner must
     still answer "go as v1.0.0", because `next-version.sh` will keep proposing `v0.1.0` (0 tags, local and
     remote). SHI-24 returns `plugin.json` to 1.0.0 and folds the README notes into one v1.0.0 section.
     Unverified consequence for the owner: a consumer on the already-installed 1.0.0 sees no version change,
     so a version-keyed plugin update would not offer them this build.
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
