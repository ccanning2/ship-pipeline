# SHI-5 — Staging sign-off

Decision: approved
Environment: staging
Commit: f9cc6aff65942cf711b2117392adcd71e66a459f
Signed: 2026-09-19

> **Template note.** The shipped `docs/pipeline/_templates/signoff.md` has "Backend" and "Frontend" test lines for a
> web product. This project has one suite (`bash tests/pipeline/run-all.sh`), so it is reported per file.
> "Staging" here is the `staging` branch ref (`PIPELINE_HAS_DEPLOY_ENVS="no"`: no host, `STAGING_URL` is only a GitHub
> tree URL). Verification method: `git fetch origin`, `origin/staging` = `f9cc6aff65942cf711b2117392adcd71e66a459f`
> (equals `Dev:` = `QA:` = `Staging:` in releases.md), exported with `git archive origin/staging` into `mktemp -d`
> directories; every check below ran on that export in throwaway git repos, never on the working tree, never against a
> real repo, tracker or network. Pushes in the walkthrough went to local bare repos only. No `PIPELINE_BYPASS`, no hook
> touched, no override used. The gate, promote and init scenarios ran on Git-Bash (Windows) and also on real Linux bash 5.2
> (WSL Ubuntu 24.04, LF copy of the export).
> `git diff 2e9552d f9cc6af --stat` (change since the first build): 19 files. Shipped code: `.claude-plugin/plugin.json`
> (SHI-24), `README.md`, `commands/pipeline-init.md` (SHI-23), `commands/ship.md` (one word), `scripts/init.sh`
> (SHI-21/22/25). Tests: 5 files. The rest is `docs/pipeline/SHI-5/*` records. Nothing surprising: `gate.sh`,
> `promote.sh`, `status.sh`, the hooks, `agents/` and `template/` are unchanged since the first build.

## Test re-run
Single suite, `bash tests/pipeline/run-all.sh`, run ONCE on the staging export, in the background, not killed
(2026-09-19T16:44Z to about 18:17Z, about 1 h 34 min; free memory stayed above 10 GB): **728 passed, 0 failed,
`ALL PIPELINE TESTS PASSED`**. Counts match qa-report.md and did not drop (613 on 2e9552d, 711 on 6a0cbbc, 728 now).

| File | Passed / total |
|---|---|
| test_config.sh | 162 / 162 |
| test_init.sh | 137 / 137 |
| test_gate.sh | 206 / 206 |
| test_promote.sh | 105 / 105 |
| test_intake_status.sh | 44 / 44 |
| test_allow_paths.sh | 21 / 21 |
| test_guard_merge.sh | 35 / 35 |
| test_deploy_scripts.sh | 18 / 18 |
| **Total** | **728 / 728** |

2 of the 728 are the `.docx` intake no-op passes (`ok ... (skipped)`, python-docx absent): owner-accepted, disclosed.
Backend/Frontend: not applicable (one suite).

## Staging verification
Roles: **PA** plugin author, **ID** installing developer, **PO** pipeline operator. My own scripts (throwaway, outside the
repo, not committed) were written independently of `tests/pipeline/lib.sh`: A = full walkthrough, B = differential against
the released 1.0.0 `gate.sh` (`git show 167445e:scripts/pipeline/gate.sh`), C = capability value and environment matrix,
D = `init.sh` matrix, E = `promote.sh` matrix. Totals: A 41 of 42 on Linux (the one miss was my own assertion that the LOCAL
base branch moves in push mode; it does not, the remote does, and that assertion passed), B 13/13 (50 gate comparisons,
0 differences), C 81/81 on both platforms, D 90/90 on Linux and 89/90 on Git-Bash (the one miss is my `md5sum` column
offset on Windows paths; re-checked with `cmp`), E 48/48 on both platforms.

| AC / flow | Role | Result | Evidence |
|---|---|---|---|
| AC-38 / metric 2: fresh `init.sh --no-deploy-envs --no-marketing`, one `User-facing: yes` ticket through ALL FIVE gates to a tag, real pushes to a local bare remote, `gh` pointed at a nonexistent path, no deploy or smoke override | ID, PO | PASS | build, dev, qa, staging and production gates pass; the production gate first refuses ("Go-live is not approved"), then passes after `Go-live: approved` and `Version: v1.0.0`; no `marketing.md`, no marketing row; PASS line `marketing=off, deploy-envs=off`; every promote line says `(no deploy: project has no deployable environments)`; tag `v1.0.0` on the staging sha locally and on the remote; the remote `staging` ref equals the sha; the dev sha is an ancestor of remote master; `releases.md` Production line and `deploy-history.md` written. Same on Linux bash |
| AC-21, AC-22, AC-23 fresh opted-out install | ID | PASS | no `scripts/deploy`, no deploy.sh/rollback.sh/smoke.sh, no `deploy.yml`; `pipeline-gate.yml`, `gate.sh`, CONTEXT.md, RELEASE_CHECKLIST.md present; both keys `"no"`; DEPLOY_WORKFLOW, HEALTH_PATH, DEV_URL, QA_URL, STAGING_URL, PRODUCTION_URL present and empty; 0 double-underscore placeholders in `pipeline.env`. Flagless install: both keys `"yes"`, deploy files present, URLs filled |
| AC-24 and SHI-22: validation before copying | ID | PASS | `--profile nope`, `--bogus`, `--no-deploy-envs=no`, `--name`, `--profile` and `--team-key` with no value, `--profile ..`, `--profile ../template`, `--no-deploy-envs --frobnicate`: exit 1 and the md5 of every file in the tree is unchanged; a non-git dir is refused with 0 files |
| AC-25, AC-26, BR-13: re-run over an existing deploy-on install with hand-edited files | ID | PASS | `--no-deploy-envs`, `--no-deploy-envs --no-marketing`, `--no-deploy-envs --force-tooling`, `--no-marketing`: `pipeline.env`, CONTEXT.md, RELEASE_CHECKLIST.md, settings.json, `deploy.yml`, pipeline-gate.yml and `scripts/deploy/*` byte-identical, reported as `kept`, and the owner is told to set the key by hand. `--force-tooling` alone refreshes only `scripts/deploy/*`, as before; project-owned files untouched (cmp) |
| AC-27 idempotency | ID | PASS | second identical opted-out run: nothing created, tree byte-identical |
| SHI-21, own method: set 9 forms of the key by hand, delete `scripts/deploy` and `deploy.yml`, then flagless AND `--force-tooling` re-runs | ID | PASS (verified) | no, bare no, single-quoted no, upper-case NO, and `"no"` followed by a comment holding an apostrophe, quotes, or a tab, and the `export` form: deploy files not recreated, `pipeline.env` byte-identical. A process-environment `PIPELINE_HAS_DEPLOY_ENVS=no` relaxes nothing (a fresh install still gets deploy files and `"yes"`) |
| SHI-25 strict side | ID | PASS (verified) | `"yes"`, empty, `no#x`, `"no"#x`, a nested-quote no, `maybe`, `false`, `"no" ;`: deploy files ARE scaffolded, as the gate would treat them |
| SHI-22 | ID | PASS (verified) | see the AC-24 row |
| SHI-23 | PA | PASS (verified) | a case-insensitive scan for hetzner, reputabill, paystack, ship-pipeline, vercel, heroku, kubernetes, stripe, slack, aws, azure, gcp and a person-name scan over `agents/`, `.claude/agents/`, `commands/`: only the generic word "Docker" in `senior-engineer.md` lines 24 and 40, unchanged since 167445e and a technology rather than a vendor, product or person. `marketing-specialist.md` unchanged since 167445e; the frontmatter of all 7 personas untouched; `agents/*` and `.claude/agents/*` identical |
| SHI-24 / AC-35 | PA | PASS (verified) | `plugin.json` version is exactly `1.0.0` (parsed); README has exactly one `### v1.0.0` (line 88) and zero `### v1.1.0`; no `1.1.0` string in README, `docs/pipeline/*.md`, `template/`, `commands/`, `agents/`, `.claude-plugin/`, `scripts/`, `profiles/`; the section names both keys, the `yes` default, "No existing install changes behaviour until its owner adds a key" and both flags. `next-version.sh SHI-5` prints `v0.1.0` (0 tags, local and origin), as disclosed; the owner answers "go as v1.0.0" (Q-4). `gate.sh` accepts `Version: v1.0.0` (walkthrough A) and no `v1.0.0` tag exists, so the tag check cannot refuse |
| AC-12 / FR-8 (release blocker): a legacy `pipeline.env` (the ten v1.0.0 keys, neither new key) behaves as v1.0.0 | PO | PASS | script B, released v1.0.0 `gate.sh` against the staging `gate.sh` on identical fixtures: 5 gate stages x 5 fixture stages x `User-facing` yes and no = 50 runs, 0 differences in exit code or message (the PASS line's two new fields excluded); 12 production mutations (no `marketing.md`, draft, ready with no done row, ready with a done row, open marketing row, open defect, High wontfix, Go-live pending, bad Version, signoff blocked, wrong env, wrong sha), all identical. User-facing with no `marketing.md` gives exit 1 `missing marketing.md`; ready with no done row gives `no completed marketing launch ticket`; full evidence gives 0; `User-facing: no` gives 0 |
| AC-13, AC-19: legacy env and `promote.sh` with deploy envs on | PO | PASS | script E with stub deploy and smoke commands: with the key absent, empty, `false`, `0`, `maybe` or `yes` the deploy stub is called and a failing smoke command blocks (exit 1); `PIPELINE_HAS_DEPLOY_ENVS=no` exported in the environment (key absent, or file `yes`) still deploys and smokes |
| AC-14..AC-18, AC-20: deploy envs off | PO | PASS | file `"no"` and `"  NO "`: the deploy stub is not called, an always-failing smoke command is not called, exit 0, the progress line says why; deploy keys entirely missing (not just empty) under `set -u`: no `unbound variable`; env `yes` cannot re-enable a file `no`; an open `eng` ticket or a dirty tree still refuses promote dev and leaves the base ref untouched |
| AC-1..AC-4: fail-closed resolution | PO | PASS | script C, production gate, `User-facing: yes`, no marketing evidence. STRICT (exit 1, `missing marketing.md`) for absent, `"yes"`, empty, `false`, `0`, `maybe`, `Y`, `off`, `NO!`, `n`, `nope`, `"no no"`, `"n o"` and unquoted `yes`. OFF (exit 0, `marketing=off`) only for `"no"`, unquoted `no`, `"No"`, `"NO"`, `"  no  "`, `'no'`, `"no"` with a trailing comment, `"no"` plus a carriage return, and `"  NO  "` |
| AC-5: the environment cannot relax anything | PO | PASS | `PIPELINE_HAS_MARKETING=no` in the environment with the key absent, and with the file `"yes"`: gate still exit 1; env `yes` cannot override a file `no`; `PIPELINE_HAS_DEPLOY_ENVS=no` (env or file) does not relax the marketing gate; `status.sh` with env-only `no` for both keys shows `marketing=on` and `deploy-envs=on` |
| AC-6..AC-11 | PO | PASS | the PASS line carries `marketing=` and `deploy-envs=`; stderr is empty on a passing run; `DEPLOY_SHA=` and `VERSION=v1.0.0` are parseable; marketing `"yes"`: draft gives `marketing.md Status is not 'ready'`, ready with no row gives `no completed marketing launch ticket`, full evidence passes; `User-facing: no` passes for any value; with marketing off, a High wontfix, an open defect, Go-live pending and a malformed Version each still fail; the `gate.sh` diff against 167445e is exactly the `&& [ "$has_marketing" = yes ]` conjunct, the capability resolver, the environment `unset` and the PASS-line fields |
| AC-32, AC-33: `status.sh` | PO | PASS | both off prints `deploy-envs=off (deploy, dispatch and smoke steps are skipped; promotion still runs) marketing=off (marketing-specialist and the production marketing requirement are skipped)`; a misspelt value prints `marketing=on (unrecognised value ...)`; exit 0. Real SHI-5 today: build, dev, qa and staging `[x]`, production `[ ]` |
| AC-28..AC-31: wording | PA, ID | PASS | `pipeline-init.md` names both flags, both owner questions and the CONTEXT.md record; `ship.md` step 7, `senior-engineer.md` and `app-specialist.md` state "project has a marketing function AND user-facing"; `product-owner.md` says `User-facing` decides no persona; personas mirrored and identical |
| AC-34: docs | ID | PASS | `TICKETS.md`, `BRANCHING.md`, `CLOUD.md`: repo copy identical to the `template/` copy; `PIPELINE_HAS_` documented in README, TICKETS, BRANCHING, CLOUD, template CONTEXT, template checklist, template `pipeline.env`, `pipeline-init.md`, `ship.md` |
| AC-36, AC-37: dogfood | PA | PASS | zero `n/a` in `scripts/pipeline/pipeline.env`; no "N/A — no image, no host" and no narrowed `User-facing` parenthetical in RELEASE_CHECKLIST.md; CONTEXT.md has no "ignore the generic docs" text and no SHI-5 bullet; both keys `"no"`. The real SHI-5 gates (working tree, read-only): build, dev, qa, staging PASS with `user-facing=yes, marketing=off, deploy-envs=off` |
| Hostile ticket text through `intake.sh` | PO | PASS | a body with command substitutions, backticks, a `; touch` and a `; rm -rf` on stdin is written literally into `brief.md`; nothing executed, the marker file was not created |
| Write boundaries, tested directly | PA | PASS | `allow-paths.sh` with the qa-tester globs: `tests/x.sh` and `qa-report.md` allowed (exit 0); `src/App.java`, `scripts/pipeline/gate.sh` and `signoff.md` blocked (exit 2, `PERSONA BOUNDARY`). `guard-merge.sh`: a push to the staging branch, a tag push and `gh release create` for a ticket with no docs are blocked (exit 2, from the real gate); a harmless command passes. (An unparseable payload exits 0: pre-existing, disclosed in QA round 1.) Plus test_allow_paths 21/21 and test_guard_merge 35/35 |
| Performance sanity | PO | PASS | `gate.sh` on the real repo, under heavy load from the running suite: about 7.6 s new against 7.0 s for the released 1.0.0 gate (two extra `tr` and `sed` subprocesses); `promote.sh` makes fewer `gh` calls with deploy envs off (none) |
| Rollback path for an installing project | ID | PASS | the released 1.0.0 `init.sh` run over an opted-out install: exit 0, tooling refreshed to the old scripts, `pipeline.env` byte-identical, and the deploy files the project never wanted recreated; the released 1.0.0 `gate.sh` runs on the new-style `pipeline.env` (unknown keys ignored) |
| Marketing | - | SKIPPED BY CONFIGURATION | `PIPELINE_HAS_MARKETING="no"` (owner decision Q-1, 2026-09-18); no `marketing.md` and no `marketing` ticket by design, not missing |

## Checklist results
| Section | Item | Result | Evidence |
|---|---|---|---|
| 1 Build & tests (blocking) | `run-all.sh` green; count at or above baseline and previous run | PASS | 728/728, `ALL PIPELINE TESTS PASSED`; 728 >= 711 (6a0cbbc) >= 613 (2e9552d) >= 419 (pre-SHI-5 baseline); per-file counts equal the expected 162/137/206/105/44/21/35/18 |
| 1 | Every AC maps to a passing test | PASS | qa-report.md R1 AC table (AC-1..AC-38, each with a named test); AC-31 and AC-35 were fixed by SHI-23 and SHI-24 and are green in the 728; AC-37 has a test plus my real-gate run |
| 1 | Staging runs exactly the dev-checked, QA-tested sha | PASS | `origin/staging` = f9cc6aff65942cf711b2117392adcd71e66a459f; releases.md `Dev:` = `QA:` = `Staging:` = f9cc6af; dev-check.md and qa-report.md `Commit:` = f9cc6af; real `gate.sh SHI-5 qa` and `staging` PASS |
| 1 | Every AC walked end-to-end from the staging ref in a throwaway repo | PASS | the verification table above |
| 2 Domain risks (blocking) | `init.sh` idempotency, never clobbers, no half-applied install | PASS | AC-24..27 rows; SHI-21, SHI-22, SHI-25 |
| 2 | `gate.sh` pass/fail conditions | PASS | one conjunct changed (owner-approved, Q-3); 50-run differential against v1.0.0 with 0 differences; fail-closed matrix; the environment cannot relax |
| 2 | Write-boundary hooks | PASS | tested directly (row above) plus the two hook suites |
| 2 | `promote.sh` and `next-version.sh` | PASS | the sha reaches remote master, the staging ref and the tag correctly; `next-version.sh` = `v0.1.0` (0 tags), the owner overrides with "go as v1.0.0" |
| 2 | Agent frontmatter | PASS | the diff of `agents/` against 167445e touches body text only, in 3 personas; no `disallowedTools`, `model` or hook line changed |
| 2 | Cross-platform shell | PASS (with notes) | Git-Bash and real Linux bash 5.2 both green; `bash -n` clean on every `.sh`; all `.sh` files mode 100755; no `sed -i` without a suffix, `grep -P`, `readlink -f`, `date -d` or backslash-s in shipped scripts. Read only, not runnable here: macOS system bash 3.2 (an empty-array expansion under `set -u`, pre-existing shape, inside a pipeline condition so it cannot abort) and BSD `sed -i -E` in `tests/pipeline/lib.sh` (QA round 1, test code only) |
| 3 Security (blocking) | No secrets in the diff; init writes only placeholder names | PASS | an added-lines scan and a whole-tree token-shape scan find only secret NAMES (`secrets.DEPLOY_SSH_KEY`, `secrets.GITHUB_TOKEN`) and prose, no key, token or password value; a fresh install writes booleans and empty strings |
| 3 | Hooks still enforce their boundaries (tested) | PASS | write-boundary row |
| 3 | Untrusted tracker text is data | PASS | hostile-brief row; capability values are only compared to a literal, never interpolated |
| 4 Data & migrations (blocking) | No database; `init.sh` never overwrites a project-owned file; no half-applied install | PASS | AC-24..27 rows |
| 4 | Rollback approach documented | PASS | Rollback plan below, by sha: the repo has ZERO tags, so the previous-version-tag wording is recorded as pending-by-design, not a failure |
| 5 Infrastructure & delivery | Plugin installs cleanly from the staging ref; `init.sh` scaffolds correctly | PASS | export of `origin/staging`, then `init.sh` into throwaway repos on two platforms. The interactive `/plugin marketplace add` and `/plugin install` commands cannot be driven from this environment; `plugin.json` parses and `commands/`, `agents/` and `.claude-plugin/marketplace.json` are present |
| 5 | The same sha reaches master, the staging branch and the tag; promote reports no deploy required | PASS (tag pending-by-design) | walkthrough A proves the mechanism end to end; for SHI-5 itself the tag is created at the production stage, after go-live |
| 5 | `plugin.json` version matches the proposed tag | PASS | `1.0.0`; owner decision Q-4 makes the tag `v1.0.0` (`next-version.sh` proposes `v0.1.0`, which is NOT a defect) |
| 5 | Previous production version tag recorded | PENDING-BY-DESIGN | no tag exists; recorded by sha instead (Rollback plan) |
| 6 Product & brand | product.md and requirements.md approved; research complete; no open clarifications | PASS | Status approved, approved, complete; Q-1..Q-4 all answered |
| 6 | `User-facing` honest; marketing recorded as skipped by configuration | PASS | `User-facing: yes` (SHI-5 does affect installing developers); marketing skipped by `PIPELINE_HAS_MARKETING="no"` (Q-1) |
| 6 | What an installing developer sees reads correctly | PASS (with notes) | README release notes, `pipeline-init.md` and `init.sh` output verified. Stale wording, not blocking: README layout says "425 tests" (actual 728); `init.sh` Next step 3 and README setup steps 2 and 4 still tell an opted-out project to create GitHub environments, deploy secrets and a host; `ship.md` step 9 and `senior-engineer.md` Mode promote-production still mention waiting for the deploy, `rollback.sh` and launch content without the capability caveat; `docs/pipeline/README.md` mentions `scripts/deploy/rollback.sh` |
| 6 | No product, person, vendor or project-type names in agents/ or commands/ | PASS | SHI-23 row; test_config AC-31 green |
| 7 Tickets (blocking) | Every `eng` done; every `defect` verified; no High wontfix | PASS | tracker (Linear, team a0d92e96-8405-445b-a2d1-6e1fa20afba3) and tickets.md agree: SHI-13..SHI-20 and SHI-24 Done; SHI-21 (Medium), SHI-22 (Low), SHI-23 (Low), SHI-25 (Low) Done = verified; no wontfix; no marketing ticket, by configuration |
| 7 | `tickets.md` matches the tracker | PASS | every row compared with the 18 sub-issues; stories SHI-7/8/9 and follow-ups SHI-10/11/12 are Backlog = open on both sides (stories are not gated; the owner may close them) |
| 8 Docs | README, BRANCHING, TICKETS, CLOUD updated; release notes; STATUS.md complete | PASS (with notes) | README, `TICKETS.md`, `BRANCHING.md`, `CLOUD.md` and their `template/` copies updated and identical; the `### v1.0.0` notes state the change and that existing installs are unaffected. No tooling path, agent name or template filename changed, so no breaking-change note is needed. STATUS.md is accurate through stage 7 and shows this stage in progress; the orchestrator closes row 8 |

## Defect tickets raised / verified
- Raised: none.
- Re-tested by me independently, fix confirmed (QA verified stands): SHI-21 (Medium), SHI-22 (Low), SHI-23 (Low), SHI-25 (Low). SHI-24 (eng, done) confirmed: `plugin.json` exactly `1.0.0`; one `### v1.0.0`, no `### v1.1.0`.

## Blocking items
- none.

Non-blocking, for the owner and the go-live summary (none of these is a gate failure):
1. **This repo has its own `.github/workflows/deploy.yml`, which is dead weight** (owner-accepted, BR-13). It triggers on pushes to `master` and `staging` and on `v*` tags and builds an image this project does not have. It WILL fail on the first such push and on the `v1.0.0` tag. The owner should disable or delete it before tagging.
2. **Version at go-live.** `next-version.sh` proposes `v0.1.0` (no tags). The owner answers "go as v1.0.0" (Q-4). Verified: `plugin.json` is `1.0.0`, the README notes match, `gate.sh` accepts `Version: v1.0.0`, and no `v1.0.0` tag exists. The released 1.0.0 (commit 167445e) and this build share the number by the owner decision, so roll back by sha, not by version.
3. `plugin.json` `description` still says "GitHub Actions + Hetzner" (a vendor name in the manifest, outside the agents/commands rule; disclosed, not blocking).
4. Owner-accepted known limits, verified rather than rediscovered; all concern how `init.sh` reads the key as text on a flagless re-run and none can delete or rewrite a file: a later export-style mention of the key makes init stricter than the gate (reproduced: the deploy files come back, `pipeline.env` untouched, gate and promote still resolve `no`); a carriage return inside the word `no`; `source` or computed-name overrides; a non-UTF-8 byte in the comment on the key line. Also the two `.docx` no-op passes.
5. Design note, not a defect: a capability is read from the branch under gate, so a ticket branch could flip `PIPELINE_HAS_MARKETING` to `no` in `pipeline.env`. That is the owner-approved model (Q-3: an explicit `no` committed by the project owner). It shows in the diff of a project-owned file, in the gate PASS line (`marketing=off`) and in `status.sh`.
6. The stale wording under checklist section 6, and the pre-existing follow-up candidates already in STATUS.md (`allow-paths.sh` does not normalise the double-dot segment; `tests/pipeline/lib.sh` uses GNU `sed -i -E`), are outside SHI-5.
7. On this Windows machine `git archive` yields CRLF working files (`core.autocrlf=true`); the committed blobs are LF, Git-Bash tolerates CRLF, and the Linux runs used LF copies.
8. Stories SHI-7, SHI-8 and SHI-9 are still open in the tracker; the owner may close them at go-live.

## Rollback plan
There is no previous version tag (the repo has ZERO tags, locally and on `origin`; `v1.0.0` is created at the production
stage, after go-live). Rollback is therefore by SHA:
- The released 1.0.0 is commit `167445ef3f1aab5d97894719e465c2e95d74ebbe` (ship-pipeline v1.0.0). The pre-SHI-5 master is
  `7b0b3ac8505ea10b08b0bae9f8789967471df941` (chore: install ship pipeline), whose parent `c0102d3` (Fix JSON formatting
  in plugin.json) follows `167445e`; all three are ancestors of the release sha `f9cc6af`. Prefer `7b0b3ac` as the target
  (the last master before SHI-5, with the manifest fix and the Windows python probe fix); `167445e` is the as-first-released
  target. Never rewrite history and never move a published tag.
- **Maintainer, before tagging:** nothing to undo; do not create the tag and leave `Go-live` unwritten.
- **Maintainer, after `v1.0.0` exists:** do NOT move or delete the pushed tag (the gate refuses a tag that already exists on a
  different sha). In a new bugfix ticket, restore the tree of `7b0b3ac` in a NEW commit on a ticket branch (check out
  `7b0b3ac` over the tree and commit, or revert the SHI-5 range), promote it through the normal gates and release it
  as `v1.0.1`. Consumers who must move at once can install the plugin from the sha `7b0b3ac` (or `167445e`) instead of the tag.
- **Installing project:** nothing to migrate. Existing installs never received the new keys and behave as v1.0.0 with or
  without them; `init.sh` never deletes or rewrites a project-owned file. To go back, re-run the `init.sh` of the older plugin
  (verified with the 167445e export): it refreshes the tooling (`scripts/pipeline/*`, hooks, agents, docs, tests), leaves
  `pipeline.env` byte-identical (the two new keys are ignored by the old scripts) and recreates any missing
  `scripts/deploy/*` and `deploy.yml`. Caveats: a project that had opted out of deployments gets deploy files and deploy
  behaviour back (fill in its URLs, or stay on the new tooling), and a project with `PIPELINE_HAS_MARKETING="no"` will again
  be asked for launch content at the production gate.
