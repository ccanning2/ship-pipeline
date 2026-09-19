# SHI-5 — QA report

Result: pass
Environment: qa
Commit: f9cc6aff65942cf711b2117392adcd71e66a459f
Suite: SCOPED re-test (owner's choice, rework loop 2/3). Run on the QA-sha export: `test_init.sh` 137 passed, 0 failed (in full, one run, in the background, about 70 min; includes the 17 QA round-2 assertions: 15 `QA2:` and the two SHI-25 `QA-DEF`, all passing) and `test_config.sh` 162 passed, 0 failed. NOT run: `run-all.sh` and the other six suites (test_gate, test_promote, test_intake_status, test_allow_paths, test_guard_merge, test_deploy_scripts), because `git diff 6a0cbbc f9cc6af` changes only `scripts/init.sh` in shipped code; those six last ran green on 6a0cbbc (711/711 with test_config 162 and test_init 120)

This file holds three rounds. **Round 3 (f9cc6af, scoped)** is the current verdict and comes first, then **Round 2
(6a0cbbc)**, then **Round 1 (2e9552d)**, its headings prefixed `R1`. The Round 2 header (Result: fail, 711/711) is
kept below as history.

## Round 3 (f9cc6af, scoped)

### Verdict
**PASS.** SHI-25 (Low) is **verified** and closed (Done). No new defect raised. SHI-21, SHI-22, SHI-23 and SHI-24 did
not regress. No High, no gate that wrongly passes, no data loss, no change for an install without the new keys.
This was a scoped re-test chosen by the owner: `test_init.sh` in full and `test_config.sh` were run, the other six
suites and `run-all.sh` were not. Four observations for the owner are listed at the end; none is raised as a defect
(reasons given), and QA will raise any of them as a Low defect if the owner says so.

### QA environment
`origin/staging` = `f9cc6aff65942cf711b2117392adcd71e66a459f` (checked after `git fetch`; equals the `QA:` sha in
`releases.md`). Exported with `git archive origin/staging` into a `mktemp -d` under `$TEMP`; every check ran on that
export, never the working tree. `git diff 6a0cbbc f9cc6af`, outside `docs/pipeline/SHI-5/`, touches exactly three
files: `scripts/init.sh` (the fix, `cf1efec`) and QA's own two test files from round 2 (`tests/pipeline/test_init.sh`
+17 assertions, `tests/pipeline/test_config.sh` AC-31 word-bounded). Nothing else in `scripts/`, `agents/`,
`commands/`, `template/`, `profiles/`, `README.md` or `.claude-plugin/` changed, so the scoped run is justified.
`bash -n scripts/init.sh` is clean. Provenance noted: the engineer agent wrote the fix and was cut off by a rate limit
before verifying or committing; the orchestrator's 49-form differential was treated as their evidence, not QA's. All
results below are QA's own.

### Suites (QA sha export)
| Suite | Result | Notes |
|---|---|---|
| `tests/pipeline/test_init.sh` | **137 passed, 0 failed** | expected 137 (120 + QA's 17). Both SHI-25 `QA-DEF` assertions pass (comment with an apostrophe, comment with a lone `"`); all 15 `QA2:` pass; the earlier SHI-21 and SHI-22 `QA-DEF` assertions still pass. One run in the background, exit 0, no memory trouble (free memory stayed above 11 GB) |
| `tests/pipeline/test_config.sh` | **162 passed, 0 failed** | expected 162; AC-31 (word-bounded scan) passes |
| the other six suites, `run-all.sh` | not run | scoped re-test; only `scripts/init.sh` changed in shipped code and no other script calls `declared_capability()` |

### SHI-25 (init.sh parser vs gate.sh) — verified
The reported case (A) and every contrived form the ticket named (B) now resolve as `gate.sh` does:
* **A, apostrophe or lone `"` in a trailing comment** (`"no"  # we don't deploy`, `no # it's off`, `no # a " mark`,
  `'no' # don't "ask"`, `export KEY=no # it's off`): honoured end to end with the real `init.sh` in a throwaway repo, and by
  the two committed `QA-DEF` assertions.
* **B, permissive forms the ticket named**: `no#x`, `"no"#x`, `'"no"'`, `"'no'"`, a later `unset`, `+=`, `declare …=yes`,
  `readonly …=yes`, `export …=yes`: init now resolves ON, as gate does. Only the documented control-flow class remains.

**Differential, QA's own** (not the orchestrator's script): 213 value forms (a superset of the round-2 82) through the
verbatim `declared_capability()` extracted from the QA-sha `init.sh`, against gate.sh's real resolution run as gate runs
it (`set -euo pipefail`, `unset`, `source`, `capability()`), and every form cross-checked against the first 40 lines of
the real `gate.sh` executed verbatim. Harness note: the first version wrongly ran the gate side inside a `&&`/`||`
list, which disables `set -e` and hid the gate's aborts; fixed and re-run. Results, Git-Bash (the QA platform):
* **145 agree.** All forms in the ticket; the new probes below; the 15 `QA2:` forms.
* **46 init stricter than gate (init ON, gate OFF): the harmless direction.** `no;`, `no ; x`, `yes; K=no`, `n\o`,
  `n"o"`, `'n'o`, `no''`, `${X:-no}`, `$(…)`, backticks, `$'no'`, `KEY+=no`, `readonly/declare/typeset/export -n KEY=no`,
  `eval "KEY=no"`, `source x; KEY=no`, `(KEY=no)`, `KEY=no &`, `KEY=yes cmd`, `KEY[0]=no`, `KEY=(no)`, self-referencing
  default, and the "key mentioned again on a later line" family (below).
* **14 forms where gate.sh itself aborts** (unparseable under `set -e`/`-u`; the gate fails closed): `no# c` glued, `9KEY=no`,
  `KEY=# no`, unbalanced quotes, `KEY = no`, BOM, `$NO`, `false && KEY=no`, `export KEY = no`, and two where init reads OFF:
  `KEY= no` and `KEY=<tab>no` (bash runs `no` as a command; the gate aborts). Harmless: no gate stage can run on that file.
* **8 permissive (init OFF, gate ON), all the documented "init does not evaluate shell" class:** `if false; then KEY=no; fi`,
  an uncalled function, a heredoc (plain and quoted), `while false`, a multi-line quoted string containing the line, and
  `if true; then KEY=yes; else KEY=no; fi`. **No other permissive form on Git-Bash.**
* **Randomised differential**: 700 files of 1 to 4 lines from a 77-fragment pool (assignments in many shapes, comments,
  `unset`, `export`, `${KEY:=…}`, arrays, mentions, CR, non-ASCII), fixed seed, against the real gate head: 412 agree, 192
  init stricter, 96 gate aborts, **0 permissive**.
* New probes asked for, all agree: `KEY=no` with tabs around; `KEY="no"   # c`; a comment-only file; `XPIPELINE_HAS_DEPLOY_ENVS=no`,
  `PIPELINE_HAS_DEPLOY_ENVS_OLD=no`, `…_ENVS2`, `_KEY`, `9KEY`, and the key inside a longer name before or after a real `no`;
  multiple `#` in a comment; `#` at the start of a value (bare and quoted); whitespace-only lines and file; 200 KB comment,
  200 KB earlier line, 100 KB padding, 2000 lines, 300 duplicate keys; no trailing newline (five variants); CRLF on some
  lines only; non-ASCII in the comment, before the key and in the value.
* **Read-only proof.** After flagless, `--force-tooling`, `--force-tooling --no-marketing` and `--no-deploy-envs` re-runs over an
  opted-out install with hand-edited `scripts/deploy/deploy.sh` and `deploy.yml`, plus hand-edited `CONTEXT.md`,
  `RELEASE_CHECKLIST.md`, `settings.json` and a key line with an apostrophe comment: `pipeline.env`, `CONTEXT.md`,
  `RELEASE_CHECKLIST.md`, `pipeline-gate.yml`, `settings.json`, `docs/pipeline/README.md`, `deploy.sh` and `deploy.yml` are byte-identical
  and the whole tree hash list is unchanged. The function body only reads (`tr < file | sed | grep | tail`).

**Also run on a real Linux bash** (WSL Ubuntu 24.04, bash 5.2, grep 3.11, `C.UTF-8`) because CI and consumers run there
and Git-Bash's bash silently ignores CR: the same 213 forms and the same 700-file fuzz (LF copies of the QA-sha scripts).
Identical to Git-Bash except one form (Observation 2 below). Fuzz: 0 permissive.

**End to end with the real `init.sh`** (35 runs in one throwaway install, key line replaced each time, deploy files
removed between runs, outcome compared with gate's real resolution): every form that gate reads OFF leaves the deploy
files uncreated and every form it reads ON recreates them, with three stricter exceptions (`no` followed by a line that
mentions the key, Observation 1: init recreates the files, gate reads OFF) and the documented `if false` permissive one; `pipeline.env` and the other project-owned files byte-identical in every
run; flagged re-runs (`--force-tooling`, `--no-marketing`, `--no-deploy-envs`, `--force-tooling --no-deploy-envs`, `--name/--team-key`,
`--profile reputabill`) over the apostrophe-comment opt-out create no deploy files; over `"yes"` (flagless and `--force-tooling`) they
come back.

### Regression check on earlier fixes
| Ticket | Result | Evidence |
|---|---|---|
| SHI-21 (Medium) | still verified | the QA2 and SHI-21 `QA-DEF` assertions pass in the 137/0 run; end-to-end flagless and `--force-tooling` re-runs over an opted-out install create no `scripts/deploy/*` or `deploy.yml`; hand-edited copies byte-identical (above) |
| SHI-22 (Low) | still verified | `--profile nope`, an unknown flag (alone and after valid flags), `--name`/`--profile`/`--team-key`/`--project-dir` with no value, `--profile ..`, `../template`, `reputabill/x`, a non-git dir (alone and with a bad profile): exit 1, 0 files. A nonexistent `--project-dir`: exit 1. `--profile ""` still installs (exit 0, 53 files) |
| SHI-23 (Low) | still verified | `grep -niE "hetzner\|reputabill\|paystack\|ship-pipeline"` and `grep -niwE "curate\|chris"` over `agents/*.md commands/*.md`: nothing; test_config AC-31 passes |
| SHI-24 / AC-35 | still met | `plugin.json` version exactly `1.0.0`; one `### v1.0.0`, zero `### v1.1.0` in README; no `1.1.0` string in README, `docs/pipeline/*.md`, `template/`, `commands/`, `agents/`, `.claude-plugin/`, `scripts/`, `profiles/` |

### Tickets
| Ticket | Severity | State | Note |
|---|---|---|---|
| SHI-21 | Medium | verified (Done) | unchanged |
| SHI-22 | Low | verified (Done) | unchanged |
| SHI-23 | Low | verified (Done) | unchanged |
| SHI-24 | - | done | AC-35 met |
| SHI-25 | Low | **verified (Done)** | the reported and named forms agree with gate.sh; QA-DEF x2 pass; remaining permissive forms are the documented text-versus-bash limit |
No new defect tickets.

### Observations for the owner (not raised as defects, and why)
1. **Stricter direction, likely the most realistic: the key mentioned again on a later line.** `PIPELINE_HAS_DEPLOY_ENVS="no"`
   followed by `export PIPELINE_HAS_DEPLOY_ENVS`, `echo $PIPELINE_HAS_DEPLOY_ENVS`, `: ${PIPELINE_HAS_DEPLOY_ENVS:=…}` or
   `[[ $PIPELINE_HAS_DEPLOY_ENVS … ]]` makes init resolve ON (the last line that mentions the key is not an assignment), while gate
   resolves OFF. Result: a flagless re-run recreates the deploy files (the SHI-21 symptom) for such a file. Confirmed with the real
   `init.sh`. Behaviour change against 6a0cbbc, which honoured the `no` here (it only looked at `KEY=` lines). Not raised: the brief
   says init may be stricter than gate for these shapes, the shipped template and init-produced files never contain such a line,
   and the fail-closed rule is respected. A one-line mitigation would be to ignore a bare `export KEY` line when picking the last mention.
2. **Permissive on real Linux/macOS bash only: a CR inside the word.** `KEY=n<CR>o` or `KEY="n<CR>o"`: init deletes every CR
   (`tr -d '\r'`) and reads `no` (OFF); a bash that keeps a mid-value CR resolves ON. Git-Bash's bash ignores CR, so it does not
   reproduce on the QA platform; reproduced on WSL Ubuntu bash 5.2. Every ordinary CR (line ending, CR before a comment, whole-file CRLF, CRLF on some lines)
   agrees. Not raised: a CR inside the token `no` cannot come from an editor's line endings; effect if it happened is omitted
   deploy files, nothing deleted. This is the only permissive form outside the documented class, so under the brief's strict rule
   it is a finding; QA judged it not worth the last rework loop. Owner decides. Fix would be `sed 's/\r$//'` instead of `tr -d '\r'`.
3. **Same "init reads text, bash evaluates" class as the documented limit but not literally listed:** a `no` followed by
   `source ./other.env` or `. ./other.env` that sets the key to `yes`, or an override through a computed variable name
   (`n=PIPELINE_HAS; export ${n}_DEPLOY_ENVS=yes`). Init OFF, gate ON. Contrived. Suggest adding `source`/`eval`/indirection to the code comment; not raised.
4. **Stricter, pre-existing, UTF-8 locales only:** a byte that is not valid UTF-8 (a Windows-1252 `’` or `é`) inside the key line's comment
   makes `sed` and `grep` skip that line (grep prints "binary file matches"), so init resolves ON and the deploy files come back. The parser
   in 6a0cbbc behaved the same. Invalid bytes on any other line do not matter; under `LC_ALL=C` it agrees. Not raised: needs a file that is not
   valid UTF-8, direction is the allowed one, and it is not a regression.

### Notes (not defects)
* `KEY= no` and `KEY=<tab>no` (whitespace right after `=`): init reads OFF, gate aborts (fails closed). The engineer noted this too.
* `git archive` on this machine yields CRLF working files (`core.autocrlf=true`); Git-Bash's bash tolerates that, which is why the suites run here. The blobs are LF.
  The Linux probe used LF copies.
* The Round 2 notes on the `deploy.yml` in this repo, the `allow-paths.sh` `..` normalisation, `next-version.sh` proposing `v0.1.0`, and the
  README "425 tests" line still stand and are outside SHI-5.
* QA edited no test source in Round 3 (the differential, fuzz and end-to-end scripts are throwaway files under `$TEMP`; committing
  them under `tests/pipeline/` would ship them to every consumer, because `init.sh` copies `tests/pipeline/*.sh`).

---

# Round 2 (6a0cbbc)

Header at the time: Result: fail · Commit: 6a0cbbcb0dc18ad251e3df9189534888c78a4a3e · Suite: 711/711 passed on the QA sha as shipped (`bash tests/pipeline/run-all.sh`, one run, in the background: test_config 162, test_init 120, test_gate 206, test_promote 105, test_intake_status 44, test_allow_paths 21, test_guard_merge 35, test_deploy_scripts 18; `ALL PIPELINE TESTS PASSED`). 2 of the 711 are the `.docx` no-op passes. QA's round-2 additions to test_init.sh (17 assertions) were run separately on the QA-sha export: 15 pass, 2 fail by design (the two `QA-DEF` SHI-25 regression assertions). test_config.sh with QA's AC-31 edit: 162/0.

### Verdict
**FAIL — one new Low defect (SHI-25); everything else passes.** SHI-21 (Medium), SHI-22 (Low) and SHI-23 (Low) are
**verified** and closed (Done); SHI-24 / AC-35 is met. No High, no gate that wrongly passes, no data loss, no change
for an install without the new keys. SHI-25 is a narrow gap in the new `init.sh` parser found while attacking the
SHI-21 fix. It is Low and non-destructive, so the product owner may agree `wontfix` instead of a second rework loop
(only High-severity defects cannot be wontfix). Until then it keeps the staging gate closed (every qa-found defect
must be verified or wontfix). Returned to the engineer (Stage: build).

### QA environment
`origin/staging` = `6a0cbbcb0dc18ad251e3df9189534888c78a4a3e` (checked after `git fetch`). The QA sha was exported with
`git archive origin/staging` into a `mktemp -d` and every check ran on that export. `git diff 2e9552d 6a0cbbc --stat`
touches `.claude-plugin/plugin.json`, `README.md`, `commands/pipeline-init.md`, `commands/ship.md`,
`scripts/init.sh`, five test files and the `docs/pipeline/SHI-5/*` records: nothing outside the list the engineer
gave, and no other file under `scripts/` changed. `bash -n` is clean on every `.sh`; `agents/*` and `.claude/agents/*`
are identical.

### Defect re-test
| Ticket | Verdict | Evidence |
|---|---|---|
| SHI-21 (Medium) flagless re-run recreated the deploy machinery | **verified** | Reported scenario fixed. 17 `pipeline.env` variants run through the real `init.sh` in throwaway repos. Honoured (no deploy files): `"no"`, bare `no`, `'no'`, `No`, `" NO "`, `no # comment`, `"no" # comment`, whole-file CRLF `NO`, `export …=no`, last-of-duplicate `no`. Strict (deploy files created, as gate.sh): commented-out key, key-prefix/suffix, empty value, missing key, missing file, empty file, unbalanced quote, `no` followed by `yes`. A process-environment `PIPELINE_HAS_DEPLOY_ENVS=no` relaxes nothing (existing or fresh install; the produced `pipeline.env` still says `yes`). In every case `pipeline.env` and `CONTEXT.md` are byte-identical afterwards, no file is deleted, and hand-edited `scripts/deploy/deploy.sh` and `deploy.yml` are byte-identical after both a flagless and a `--force-tooling` re-run. init reads only `pipeline.env` (grep/sed, never sourced). A parser gap remains for a comment containing an apostrophe: SHI-25. |
| SHI-22 (Low) unknown `--profile` rejected after files were copied | **verified** | `--profile nope`: exit 1, 0 files. Every other early exit also creates nothing: unknown flag (alone and after valid flags), `--name` / `--profile` / `--team-key` / `--project-dir` with no value (exit 1, `$2: unbound variable`), non-git dir, non-git dir plus bad profile, nonexistent `--project-dir`, `--profile ..`, `../template`, `reputabill/x`, and a profile dir with only CONTEXT.md, only RELEASE_CHECKLIST.md or neither (exit 1, 0 files). `--profile ""` still means no profile (unchanged); `--profile reputabill` still installs. |
| SHI-23 (Low) vendor name in `commands/pipeline-init.md` | **verified** | `grep -niE "hetzner\|reputabill\|paystack\|ship-pipeline"` and `grep -niwE "curate\|chris"` over `agents/*.md commands/*.md` return nothing. The persona agnosticism loop and the `/ship` scan pass. The "accurate" to "correct" edit in `commands/ship.md` is harmless. Outside AC-31's scope and pre-existing: `.claude-plugin/plugin.json` `description` still says "GitHub Actions + Hetzner". |
| SHI-24 (eng) / AC-35 | **met** | `plugin.json` version is exactly `1.0.0`; README has one `### v1.0.0` and zero `### v1.1.0`; the v1.0.0 section has a "First release" group and the "Added in this release" group with the `PIPELINE_HAS_DEPLOY_ENVS`, `PIPELINE_HAS_MARKETING` and `--no-deploy-envs` bullets; no `1.1` / `v1.1.0` string in README, `docs/pipeline/*.md`, `template/`, `commands/`, `agents/`, `plugin.json`, `scripts/`, `profiles/` (the `docs/pipeline/SHI-*` records are excluded). `next-version.sh` still proposes `v0.1.0` (no tags): expected, resolved by the owner's "go as v1.0.0" at go-live, not a defect. |

### init.sh vs gate.sh divergence hunt (the new parser)
`init.sh` gained `declared_capability()`, a text scanner; `gate.sh` and `promote.sh` `source` the file. A differential of
the verbatim function (extracted from the QA-sha `init.sh`) against gate's exact `source` + `capability()` over **82 value forms**:
* **Agree (about 50):** every form in the task list (`No`, ` no `, `"no"`, `'no'`, `no # comment`, `"no" # comment`, CRLF, `export`, duplicates in both orders, commented-out, key-prefix/suffix, empty, empty quoted, `n"o"`, `"n"o`, `""no`, `no""`, `'n'o`, `"\"no\""`, `"no # comment"`, `off`/`false`/`0`, `yes # no`, no-then-yes, no-then-empty, no-then-`:=`, no-then-`export yes`, missing or empty file).
* **Init stricter than gate (harmless direction):** where gate itself errors out (BOM, `KEY = no`, unbalanced quote), `n\o`, `no;`, `no ; x`, `yes; K=no`, `$NO`, `${X:-no}`, `$(…)`, backticks; **and the realistic one, an apostrophe or a lone `"` in the trailing comment (`"no"  # we don't deploy`): init resolves ON, gate resolves OFF, so the deploy files come back (the SHI-21 symptom).** Confirmed end to end with the real `init.sh`.
* **Init reads OFF where gate resolves ON (the permissive direction), all contrived:** `no#x`, `"no"#x`, `'"no"'`, `"'no'"`, a `no` inside `if false`, an uncalled function or a heredoc, and a later `unset` / `+=` / `declare …=yes` / `readonly …=yes`. Effect: init omits deploy files for a project promote.sh will treat as deployable. Nothing is deleted or overwritten.
All raised together as **SHI-25 (Low)** with a suggested exact-line-shape fix. Regression tests committed: two `QA-DEF` assertions (comment with an apostrophe, comment with a lone `"`) that fail by design until it is fixed, plus 15 `QA2:` assertions that pin the agreeing forms and the env-only rule.

### Regression check on the rework
| Check | Result | Evidence |
|---|---|---|
| Full suite on the QA-sha export | pass | 711 passed, 0 failed (162, 120, 206, 105, 44, 21, 35, 18). One run, in the background, about 1 h 40 min; not killed; free memory stayed above 13 GB |
| Per-file counts vs the last green (613 on 2e9552d: 156, 89, 172, 83, 39, 21, 35, 18) | pass | +6 config, +31 init, +34 gate, +22 promote, +5 intake_status; allow_paths, guard_merge, deploy_scripts unchanged. Nothing dropped |
| `.docx` intake tests | as before | 2 no-op passes (no python-docx) |
| gate.sh / promote.sh / status.sh changed | none | `git diff 2e9552d 6a0cbbc -- scripts/` shows only `init.sh` |
| Default (no flags) fresh install unchanged | pass | deploy files present, both keys `yes` (test_init AC-22) |
| Other early-exit paths still precede every copy | pass | see the SHI-22 row |

### Test changes by QA (test sources only)
* `tests/pipeline/test_config.sh`, the AC-31 scan (formerly line 64): the engineer left this to QA and QA agrees it was a test bug. The `curate` match is now word-bounded (`grep -niwE "curate"`) while `hetzner|reputabill|paystack|ship-pipeline` are still matched anywhere (so `HetznerCloud` is caught; ordinary words such as "accurate" are not). Same `AC-31:` label, still one assertion; the file is 162/0 with the edit (run on the QA-sha export). The engineer's `commands/ship.md` edit stays.
* `tests/pipeline/test_init.sh` (+17): 14 `rerun_with` cases over the value forms above, one env-only case and two `QA-DEF` (SHI-25) cases. Byte-identity of `pipeline.env` and `CONTEXT.md` is asserted in each; a guard fails the block if the base install is missing.

### Tickets
| Ticket | Severity | State | Note |
|---|---|---|---|
| SHI-21 | Medium | verified (Done) | fixed for the reported case; residue is SHI-25 |
| SHI-22 | Low | verified (Done) | |
| SHI-23 | Low | verified (Done) | |
| SHI-24 | - | done | AC-35 met |
| SHI-25 | Low | open | new: init parser vs gate resolution (apostrophe in a trailing comment; contrived permissive forms) |

### Notes for the owner and engineer (not defects)
* **Owner decision, SHI-25:** fix it (one more rework loop, then re-promote through dev and QA, since any code change restarts at dev) or agree `wontfix` (Low) with the product owner and document "keep the trailing comment on that line free of quotes". Only the reporter marks a defect verified; a wontfix needs the product owner's agreement in a comment.
* **Behaviour change, not a defect:** a project whose `pipeline.env` says `no` and which still has `scripts/deploy/*` no longer has them refreshed by `--force-tooling` (before the fix it did). The files are project-owned and stay untouched.
* The round-1 notes on this repo's `deploy.yml` and the `allow-paths.sh` `..` normalisation still stand and are outside SHI-5. `deploy.yml` will fail on the first push to master/staging and on the `v1.0.0` tag; disable or delete it before tagging.
* An unparseable line in `pipeline.env` (a BOM, `KEY = no`, an unterminated quote) makes `gate.sh` exit non-zero, i.e. it fails closed. Pre-existing, outside SHI-5.
* A full `run-all.sh` takes about 1 h 40 min on this machine under Git-Bash and completed without memory trouble.

---

# Round 1 (2e9552d)

Result: fail · Commit: 2e9552d30b45ee5db894b3702bd83bdd35c76ce1 · Suite: 613/613 passed on the QA sha as shipped (156, 89, 172, 83, 39, 21, 35, 18); QA's own additions were run separately: 91 pass, 4 fail by design (defect regression tests).

> **Template note.** The shipped `docs/pipeline/_templates/qa-report.md` has "Backend tests" and
> "Frontend tests" lines for a web product. This project has one suite (`bash tests/pipeline/run-all.sh`),
> so one count is reported (as impl-notes.md did). "Environment: qa" is the `staging` branch ref
> (`PIPELINE_HAS_DEPLOY_ENVS="no"`, there is no host and no `QA_URL` to hit): the QA sha was exported with
> `git archive origin/staging` into a `mktemp -d` and everything below ran on that export. `origin/staging`
> = `2e9552d`. `git diff 2e9552d HEAD` touches only `docs/pipeline/SHI-5/{STATUS,deploy-history,dev-check,releases}.md`
> (verified), so the working tree's later commits are records, not code.

## R1 Verdict
**FAIL — three defects raised** (SHI-21 Medium, SHI-22 Low, SHI-23 Low), none of them a gate that wrongly
passes, data loss, or a behaviour change for an install without the new keys. The core of the change held
up under attack: the fail-closed resolution, the single changed gate condition, backwards compatibility
(88-comparison differential against the v1.0.0 `gate.sh`: zero differences), promote.sh skipping,
and init.sh never deleting or rewriting anything on re-runs. Returned to the engineer (Stage: build).

## R1 AC coverage
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

## R1 QA environment checks
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

## R1 Tests added
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

## R1 Defect tickets raised / verified
| Ticket | Severity | State | Test |
|---|---|---|---|
| SHI-21 | Medium | open | test_init.sh `QA-DEF: pipeline.env says no deployable environments, so scripts/deploy is not recreated` (+ deploy.yml) |
| SHI-22 | Low | open | test_init.sh `QA-DEF: an unknown profile creates nothing (no half-applied install)` |
| SHI-23 | Low | open | test_config.sh `AC-31: no vendor/product name in agents/*.md or commands/*.md` |

No defect from an earlier stage existed to re-verify.

## R1 Notes for the owner and engineer (not defects)
- **AC-35, `next-version.sh` = `v0.1.0`.** Confirmed (0 tags). Agree with not creating the tag (pushing `v*` fires this repo's `deploy.yml`). The owner must either tag `v1.0.0` on the released commit or answer "go as v1.1.0" at go-live.
- **`deploy.yml` in this repo** will fail on every push to master/staging and on the version tag. Agree it stays out of this ticket; recommend a follow-up (or disabling it) *before* the v1.1.0 tag is pushed.
- **Pre-existing, outside SHI-5, worth a follow-up:** `scripts/pipeline/hooks/allow-paths.sh` does not normalise `..`, so `tests/../src/App.java` matches `tests/*` and a persona could write outside its boundary (verified with a real hook run; the SHI-5 backslash normalisation is not the cause and does not weaken anything). An unparseable tool payload also exits 0 (allow).
- **Pre-existing, macOS:** `tests/pipeline/lib.sh` uses `sed -i -E …` (GNU form) in `set_field`, `set_ticket`, `ready_build`, `built`; BSD sed treats `-E` as the backup suffix. Shipped scripts use `sed -i.bak` correctly. `init.sh` expands `"${kept[@]}"` under `set -u`, which errors on bash < 4.4 when the array is empty (new use on the `--no-deploy-envs` path; `created[@]` had the same shape before). Not runnable here; read only.
- The `init.sh` closing "Next" step 3 and README step 2 still tell an opted-out project to create GitHub environments and deploy secrets. Spec §3.4 only asks the message to mention the capabilities, so not raised.
- README's layout table still says "425 tests" (now 613+). `docs/pipeline/README.md` still mentions `scripts/deploy/rollback.sh` for projects that have none.
- Extra stdout: a default (deploy-on) `promote.sh <T> staging` now prints one `PROMOTE [...]: staging -> <sha> (staging deploy)` line it did not print before. Engineer-disclosed; harmless.
- `gate.sh` trims only leading/trailing whitespace where the owner-approved snippet in requirements §4.2 used `tr -d '[:space:]'` (which would also turn `n o` into `no`). The implementation is stricter than the approved text, in the safe direction; noted for the record.
