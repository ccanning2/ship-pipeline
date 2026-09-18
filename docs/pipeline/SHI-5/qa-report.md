# SHI-5 — QA report

Result: fail
Environment: qa
Commit: 2e9552d30b45ee5db894b3702bd83bdd35c76ce1
Suite: 613/613 passed on the QA sha as shipped (`bash tests/pipeline/run-all.sh`: 156, 89, 172, 83, 39, 21, 35, 18; `ALL PIPELINE TESTS PASSED`). 2 of the 613 are the `.docx` no-op passes. QA's own additions (below) were run separately: 91 pass, 4 fail by design (defect regression tests)

> **Template note.** The shipped `docs/pipeline/_templates/qa-report.md` has "Backend tests" and
> "Frontend tests" lines for a web product. This project has one suite (`bash tests/pipeline/run-all.sh`),
> so one count is reported (as impl-notes.md did). "Environment: qa" is the `staging` branch ref
> (`PIPELINE_HAS_DEPLOY_ENVS="no"`, there is no host and no `QA_URL` to hit): the QA sha was exported with
> `git archive origin/staging` into a `mktemp -d` and everything below ran on that export. `origin/staging`
> = `2e9552d`. `git diff 2e9552d HEAD` touches only `docs/pipeline/SHI-5/{STATUS,deploy-history,dev-check,releases}.md`
> (verified), so the working tree's later commits are records, not code.

## Verdict
**FAIL — three defects raised** (SHI-21 Medium, SHI-22 Low, SHI-23 Low), none of them a gate that wrongly
passes, data loss, or a behaviour change for an install without the new keys. The core of the change held
up under attack: the fail-closed resolution, the single changed gate condition, backwards compatibility
(88-comparison differential against the v1.0.0 `gate.sh`: zero differences), promote.sh skipping,
and init.sh never deleting or rewriting anything on re-runs. Returned to the engineer (Stage: build).

## AC coverage
Before QA every AC except AC-37 had a test; QA added or strengthened tests for the rows marked **+**.

| AC | Test(s) | Status |
|---|---|---|
| AC-1 | test_gate.sh "AC-1/AC-7: marketing=no + user-facing passes without marketing evidence" | pass |
| AC-2 | test_gate.sh "AC-2/AC-3: PIPELINE_HAS_MARKETING=\"\" resolves strict" (+ `missing marketing.md`) | pass |
| AC-3 | test_gate.sh loop `"" false 0 maybe Y off NO!` **+** `n`, `nope`, `"no no"`, `"n o"`, `no # c` inside quotes, embedded newline | pass |
| AC-4 | test_gate.sh `"  NO  "`, `no` + CR **+** tab-padded, unquoted `no`+CR, `'no'`, `No`, `no # comment`, duplicate key (last wins, both ways) | pass |
| AC-5 | test_gate.sh "AC-5: the environment cannot relax a project that never set the key" **+** env `yes` cannot override a file `no`, env `no` cannot override a file `yes` | pass |
| AC-6 | test_gate.sh AC-6 (PASS line, DEPLOY_SHA parseable, empty stderr) | pass |
| AC-7 | test_gate.sh AC-7 (incl. `VERSION=` still printed) | pass |
| AC-8 | test_gate.sh REP-64 sequence (defect, High wontfix, signoff, go-live, version) | pass |
| AC-9 | test_gate.sh AC-9 (three messages, in order) | pass |
| AC-10 | test_gate.sh AC-10 (yes and no) | pass |
| AC-11 | test_gate.sh REP-64 four stages with marketing off; existing build/dev/qa/staging assertions untouched **+** deploy-envs=no does not relax the marketing condition | pass |
| AC-12 | test_gate.sh legacy matrix (5 stages x both `User-facing`, 4 anchors) **+** QA differential vs the v1.0.0 `gate.sh` (below) | pass |
| AC-13 | test_promote.sh AC-13 (deploy + smoke at every stage on a legacy env) | pass |
| AC-14 | test_promote.sh AC-14 (log empty across dev/qa/staging/production) | pass |
| AC-15 | test_promote.sh AC-15/AC-38 (`PIPELINE_SMOKE_CMD=false` exits 0) | pass |
| AC-16 | test_promote.sh AC-16 (sha on master, staging ref, tag, releases.md, deploy-history, commit, sync) | pass |
| AC-17 | test_promote.sh AC-17 | pass |
| AC-18 | test_promote.sh AC-18 **+** the deploy keys entirely *missing* (not just empty) under `set -u`, through dev/qa/staging | pass |
| AC-19 | test_promote.sh AC-19 (absent, `maybe`) **+** a failing smoke still blocks in both cases | pass |
| AC-20 | test_promote.sh AC-20 | pass |
| AC-21 | test_init.sh AC-21 | pass |
| AC-22 | test_init.sh AC-22 | pass |
| AC-23 | test_init.sh AC-23 **+** the produced env sources under `set -u` with empty deploy keys | pass |
| AC-24 | test_init.sh AC-24 **+** `--no-deploy-envs=no`, `-no-deploy-envs`, flag + bogus, stray positional, misspelt `--force-toolin`: all exit 1, nothing created | pass |
| AC-25 | test_init.sh AC-25 **+** re-run matrix over six flag combinations, nine project-owned files byte-identical | pass |
| AC-26 | test_init.sh AC-26 + the existing "--force-tooling refreshes deploy scripts" | pass |
| AC-27 | test_init.sh AC-27 (idempotent, opted-out project's own suite green) | pass |
| AC-28 | test_init.sh AC-28 | pass |
| AC-29 | test_config.sh AC-29 + `/ship` stage order **+** step 7 names both conditions (`marketing function **and** User-facing: yes`) | pass |
| AC-30 | test_config.sh product-owner assertion | pass |
| AC-31 | test_config.sh agnosticism loop (agents only) **+** scan of `agents/` and `commands/` for vendor/product names | **fail** — SHI-23 |
| AC-32 | test_intake_status.sh AC-32 | pass |
| AC-33 | test_intake_status.sh AC-33 **+** `" No "`, CR `no`, typo in the deploy-envs key, `false` surfaced as unrecognised | pass |
| AC-34 | test_config.sh AC-34 (both copies, `PIPELINE_HAS_` present, copies agree) | pass |
| AC-35 | test_config.sh (`plugin.json` = 1.1.0, v1.1.0 release notes). The `next-version.sh` half is **not met**: proposes `v0.1.0` (no tags). Engineer-disclosed; owner decision, see below | partial |
| AC-36 | test_config.sh AC-36 | pass |
| AC-37 | **+** test_gate.sh: this repo's committed `pipeline.env` copied into a fixture passes a user-facing ticket at the production gate with no marketing evidence | pass |
| AC-38 | test_promote.sh AC-38 **+** a real `init.sh --no-deploy-envs --no-marketing` install (no fixture patching, no deploy/smoke overrides, `gh` pointed at a nonexistent path) walked dev to a version tag | pass |

## QA environment checks
| Check | Result | Evidence |
|---|---|---|
| Clean export of the QA sha; later commits are docs-only | pass | `git archive origin/staging`; `git diff 2e9552d HEAD --name-only` = 4 files under `docs/pipeline/SHI-5/` |
| `bash -n` on every `scripts/**/*.sh`, `template/**/*.sh`, `tests/**/*.sh` | pass | no output |
| All `.sh` files mode 100755 in the tree | pass | `git ls-tree` |
| `agents/*.md` and `.claude/agents/*.md` identical (7 files) | pass | `cmp` on `2e9552d` blobs |
| Persona frontmatter (`disallowedTools`, `model`, hooks) untouched | pass | the diff of `agents/` is body text only |
| Repo docs and `template/docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md` agree; both keys documented | pass | test_config AC-34; `PIPELINE_HAS_` present in README, TICKETS, BRANCHING, CLOUD, template CONTEXT, template checklist, template `pipeline.env`, `commands/pipeline-init.md`, `commands/ship.md` |
| No vendor/product/project-type names in `agents/*.md`, `commands/*.md` | **fail** | `commands/pipeline-init.md:18` "Hetzner hosts" — SHI-23 |
| gate.sh: exactly one pass/fail condition changed | pass | diff of `gate.sh`: `[ "$uf" = yes ] && [ "$has_marketing" = yes ]`; PASS line text; nothing else. Owner approval Q-3 on record |
| Legacy `pipeline.env` (no new keys): gate identical to v1.0.0 | pass | differential: v1.0.0 `gate.sh` vs QA `gate.sh` on the same fixtures, 88 stage/mutation comparisons (5 stages base + 18 mutations x staging/production + code-change x qa/staging/production, for `User-facing: yes` and `no`): 0 differences in exit code or message (PASS line's two new fields excluded) |
| Capability value adversarial matrix on the production gate | pass | off only for `no`, `No`, `NO`, `'no'`, `" no "`, tab-padded, `no # comment`, `no`+CR (quoted or not), `""no""`, last-of-duplicate `no`, `export … =no`; strict for `n`, `0`, `false`, `off`, `nope`, `"no no"`, `"n o"`, `"no # comment"`, `"\"no\""`, embedded newline (either order), empty, absent, `NO!`, last-of-duplicate `yes` |
| Environment-only capability cannot relax anything (gate, promote, status) | pass | `PIPELINE_HAS_MARKETING=no` exported + key absent: production gate still fails; `PIPELINE_HAS_DEPLOY_ENVS=no` exported: promote still deploys; status shows `marketing=on` |
| `PIPELINE_HAS_MARKETING=no` with `User-facing: yes`/`no` | pass | both pass without marketing evidence; every other production rule still fails as before (AC-8) |
| Marketing off with stale half-written `marketing.md` present | pass | passes (file not consulted); with marketing on the same file fails on `Status` — differential "mkt draft" |
| Whole-file CRLF `pipeline.env` (every line CRLF, key CRLF) | pass | build and production gates pass with `marketing=off` |
| Deploy-envs off, `*_URL` / `DEPLOY_WORKFLOW` / `HEALTH_PATH` empty **or missing** under `set -u` | pass | promote dev/qa/staging exit 0, no `unbound variable` |
| init.sh unknown/duplicate/misplaced flags create nothing | pass | 7 bad argument lists ad hoc, 6 in the committed test: exit 1, 0 files; duplicates and flags-before-`--project-dir` fine |
| init.sh unknown `--profile` creates nothing | **fail** | 42 files written before exit 1 — SHI-22 (pre-existing) |
| init.sh re-run over an existing install, every flag combination, deletes/rewrites nothing | pass | 6 combinations; scripts/deploy/*, deploy.yml, pipeline-gate.yml, pipeline.env, CONTEXT, checklist, settings.json byte-identical; `--force-tooling` alone still refreshes deploy scripts (today's behaviour) |
| `--force-tooling` with `--no-deploy-envs` does not resurrect deploy scripts | pass | test_init AC-26 + matrix |
| Flagless re-run over an opted-out install | **fail** | recreates `scripts/deploy/*` and `deploy.yml` — SHI-21 |
| status.sh with typo values, `" No "`, CR `no` | pass | `marketing=off`; `deploy-envs=on (unrecognised value 'flase' …)`; exit 0 |
| Cross-platform read of changed scripts | pass with notes | no `sed -i` without suffix, `grep -P`, `readlink -f`, `date -d`, or `\s` in shipped scripts; trimming uses `[[:space:]]` in `sed -E`. See "Notes" |
| next-version.sh proposal | as disclosed | `v0.1.0`: repo has 0 tags (local and `origin`) |
| this repo's `deploy.yml` | as disclosed | triggers on push to master/staging and `v*` tags and builds an image; dead weight for this project. Not deleted (BR-13); owner decision |
| `.docx` intake tests | as disclosed | print `ok (skipped)` without python-docx (2 no-op passes in the count) |
| test_config `plugin.json valid` rewrite | verified intentional | the `commands`/`agents` keys were removed by the owner's own commit `c0102d3` ("Fix JSON formatting in plugin.json") one day earlier; the weaker check matches the manifest |
| Full suite on the QA-sha export | pass | 613 passed, 0 failed, run once in the background (2026-09-18T17:26Z to 19:59Z, about 2.5 h on Git-Bash); matches the engineer's 613/0 |

## Tests added
All in `tests/pipeline/` (test sources only), committed on `feature/SHI-5-change-workflow-persona-usage`:
- `test_gate.sh` (+34 assertions): capability value edge cases; deploy-envs=no relaxes nothing; env cannot override in either direction; AC-37 with this repo's own `pipeline.env`.
- `test_promote.sh` (+22): env var cannot switch deploys off; absent/unrecognised value still smokes; `"  No "`+CR and missing deploy keys; real `init.sh --no-deploy-envs --no-marketing` install walked to a version tag with no overrides (AC-38).
- `test_init.sh` (+32): argument validation before writes (six bad lists), duplicate/misordered flags, `--no-marketing` alone, opted-out env sources under `set -u`, six-combination re-run matrix over nine project-owned files, and the two defect regression tests below.
- `test_config.sh` (+2): `/ship` step 7 names both conditions; no vendor/product name in `agents/` and `commands/`.
- `test_intake_status.sh` (+5): status trimming/lowercasing/CR and typo surfacing for either key.

Four assertions in two files are **expected to fail until the defects are fixed** (they are the regression tests):
`QA-DEF: an unknown profile creates nothing` (SHI-22), the two `QA-DEF: ... scripts/deploy is not recreated` /
`... deploy.yml` (SHI-21), and `AC-31: no vendor/product name in agents/*.md or commands/*.md` (SHI-23). If any of these defects is
marked wontfix with product-owner agreement, QA removes the matching assertion.

## Defect tickets raised / verified
| Ticket | Severity | State | Test |
|---|---|---|---|
| SHI-21 | Medium | open | test_init.sh `QA-DEF: pipeline.env says no deployable environments, so scripts/deploy is not recreated` (+ deploy.yml) |
| SHI-22 | Low | open | test_init.sh `QA-DEF: an unknown profile creates nothing (no half-applied install)` |
| SHI-23 | Low | open | test_config.sh `AC-31: no vendor/product name in agents/*.md or commands/*.md` |

No defect from an earlier stage existed to re-verify.

## Notes for the owner and engineer (not defects)
- **AC-35, `next-version.sh` = `v0.1.0`.** Confirmed (0 tags). Agree with not creating the tag (pushing `v*` fires this repo's `deploy.yml`). The owner must either tag `v1.0.0` on the released commit or answer "go as v1.1.0" at go-live.
- **`deploy.yml` in this repo** will fail on every push to master/staging and on the version tag. Agree it stays out of this ticket; recommend a follow-up (or disabling it) *before* the v1.1.0 tag is pushed.
- **Pre-existing, outside SHI-5, worth a follow-up:** `scripts/pipeline/hooks/allow-paths.sh` does not normalise `..`, so `tests/../src/App.java` matches `tests/*` and a persona could write outside its boundary (verified with a real hook run; the SHI-5 backslash normalisation is not the cause and does not weaken anything). An unparseable tool payload also exits 0 (allow).
- **Pre-existing, macOS:** `tests/pipeline/lib.sh` uses `sed -i -E …` (GNU form) in `set_field`, `set_ticket`, `ready_build`, `built`; BSD sed treats `-E` as the backup suffix. Shipped scripts use `sed -i.bak` correctly. `init.sh` expands `"${kept[@]}"` under `set -u`, which errors on bash < 4.4 when the array is empty (new use on the `--no-deploy-envs` path; `created[@]` had the same shape before). Not runnable here; read only.
- The `init.sh` closing "Next" step 3 and README step 2 still tell an opted-out project to create GitHub environments and deploy secrets. Spec §3.4 only asks the message to mention the capabilities, so not raised.
- README's layout table still says "425 tests" (now 613+). `docs/pipeline/README.md` still mentions `scripts/deploy/rollback.sh` for projects that have none.
- Extra stdout: a default (deploy-on) `promote.sh <T> staging` now prints one `PROMOTE [...]: staging -> <sha> (staging deploy)` line it did not print before. Engineer-disclosed; harmless.
- `gate.sh` trims only leading/trailing whitespace where the owner-approved snippet in requirements §4.2 used `tr -d '[:space:]'` (which would also turn `n o` into `no`). The implementation is stricter than the approved text, in the safe direction; noted for the record.
