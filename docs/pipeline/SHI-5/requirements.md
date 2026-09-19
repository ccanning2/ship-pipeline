# SHI-5 — Requirements (engineer-ready)

Status: approved
Traces to: product.md (9 stories US-1..US-9, 16 rules BR-1..BR-16), research.md, clarifications.md (Q-1, Q-2, Q-3, Q-4)

> **Amendment 2026-09-19 (Q-4) — the release version is v1.0.0, not v1.1.0.**
> The owner decided (clarifications.md Q-4, answered 2026-09-19) that **this build is released as
> v1.0.0**. This document originally specified v1.1.0; **FR-30**, **AC-35**, the §8 "Version"
> paragraph and the §8 "Rollback" paragraph are edited in place to that decision, and the AC-12
> wording that referred to a "pre-1.1.0 install" is reworded. Nothing else changes: no FR or AC is
> renumbered, removed or weakened.
> This **supersedes product.md BR-10's "bump the minor version" instruction — and the matching
> `docs/pipeline/CONTEXT.md` engineering rule — for this release only**, by the owner's explicit
> decision. It is recorded here rather than in product.md because product.md is the product owner's
> file and is not edited by this amendment; BR-10 remains the standing rule for every later release.
> Consequences the owner was given before deciding: `.claude-plugin/plugin.json` returns to `1.0.0`;
> the README carries **one** release-notes section for v1.0.0 (no `### v1.1.0` heading, and not a
> second `### v1.0.0` heading); the already-released 1.0.0 (commit `167445e`) and this build
> therefore carry the same version number; and at go-live `next-version.sh` will still propose
> `v0.1.0` (the repo has no tags), which the owner overrides with "go as v1.0.0".
> The engineering work is one eng ticket, **SHI-24**, which amends **SHI-19** — SHI-19 stays
> `done` and is not reopened. It belongs to rework loop 1/3 and must land **before** the fixed build
> is re-promoted to dev, so QA tests the final content once.

> **Template note.** The shipped `docs/pipeline/_templates/requirements.md` carries section headings
> from an unrelated web product ("API contract", "UI changes", "Permissions matrix", "Data model").
> This project is a Bash/Markdown Claude Code plugin: no database, no HTTP API, no roles. The
> sections below keep the template's *intent* and map it onto what this project actually has:
> **Data model → config schema** (`pipeline.env` keys), **API contract → script contracts**
> (`gate.sh` / `promote.sh` / `init.sh` behaviour and exit codes, `/ship` and `/pipeline-init`),
> **UI → operator-visible surface** (docs wording, command output, `status.sh`).
> **Permissions matrix: N/A** — there are no roles. Template contamination is tracked as SHI-10 and
> is deliberately not fixed here.

---

## 1. Functional requirements

### 1.1 Configuration schema — the two capability keys

- **FR-1 (US-1, US-2, US-4)** `scripts/pipeline/pipeline.env` gains exactly **two new optional
  keys**, and no others:
  - `PIPELINE_HAS_DEPLOY_ENVS` — does this project have deployable environments (hosts, an image, a
    deploy workflow, a health endpoint)?
  - `PIPELINE_HAS_MARKETING` — does this project have a marketing function?

  They are independent (BR-1): any of the four combinations is valid. Every pipeline script must run
  unchanged when neither key is present.

- **FR-2 (US-4, BR-5, BR-8)** **Resolution and fail-closed defaults.** For each key, the raw value is
  trimmed of surrounding whitespace and lowercased. The resolved capability is **off** if and only if
  the result is the exact string `no`. Every other outcome resolves **on**: key absent, key present
  but empty, `yes`, `false`, `0`, `off`, `n`, `true`, `NO!`, or any typo. "On" is today's behaviour in
  both cases, so a missing key is indistinguishable from today.

- **FR-3 (US-2, BR-3)** **Project-level only, no per-ticket override.** The capabilities are read
  **only** from `scripts/pipeline/pipeline.env`. A value present in the process environment but not
  in `pipeline.env` must not change any script's behaviour. (`PIPELINE_HAS_MARKETING=no bash
  scripts/pipeline/gate.sh SHI-5 production` on a project whose `pipeline.env` does not set the key
  must behave exactly as if the variable were not set at all.) This differs deliberately from
  `PIPELINE_TICKET_REGEX`, which is written as `"${PIPELINE_TICKET_REGEX:-…}"` and *is*
  environment-overridable.

- **FR-4 (US-6, US-8)** `template/scripts/pipeline/pipeline.env` documents both keys, their allowed
  values (`yes | no`) and their defaults, in the same one-line-comment style as the existing keys.

- **FR-5 (US-9)** `gate.sh`'s success line reports the resolved capabilities, so an operator reading
  a passing gate can see which rules applied. See §3.1.

### 1.2 `gate.sh` — the only pass/fail condition that changes

- **FR-6 (US-2, US-3, BR-4, BR-9)** At the **production** stage, the marketing requirement becomes
  conditional on *both* the project capability **and** the ticket's `User-facing` flag. Exact
  before/after in **§4 — this is the change the owner approves (Q-2).**

- **FR-7 (US-5, BR-6, BR-7)** **No other `gate.sh` pass/fail condition changes.** The build, dev, qa
  and staging stages are untouched; within the production stage every condition other than the
  marketing one is untouched. `PIPELINE_HAS_DEPLOY_ENVS` changes **nothing** in `gate.sh` — the
  deploy/smoke/health machinery it governs lives in `promote.sh` and `init.sh`, not in the gate. The
  enumerated list of unchanged conditions is in **§4.3**; that list is part of the requirement.

- **FR-8 (US-4, BR-5)** **Backwards compatibility is a release blocker.** A `pipeline.env` containing
  none of the new keys must produce identical gate outcomes (exit code and failure message) before
  and after this release, at every one of the five stages, for both `User-facing: yes` and
  `User-facing: no`. Proven by a test, not by inspection — see AC-12 for the required test shape.

- **FR-9 (US-2, BR-8)** **Fail closed.** `PIPELINE_HAS_MARKETING` set to an unrecognised value —
  empty string, `false`, `0`, `maybe`, `Off`, `y` — keeps the strict (today's) production-gate
  behaviour: a user-facing ticket still requires `marketing.md` `Status: ready` and a `done`
  `marketing` row. It must never resolve permissive.

### 1.3 `promote.sh` — deploy, dispatch and smoke become conditional

- **FR-10 (US-1)** When `PIPELINE_HAS_DEPLOY_ENVS` resolves **off**, `promote.sh` performs **none** of:
  - waiting on a deploy run (`wait_for_deploy`, i.e. the `gh run list --workflow "$DEPLOY_WORKFLOW"`
    poll at `scripts/pipeline/promote.sh:59-69`) for any of `dev|qa|staging|production`;
  - the staging `gh workflow run "$DEPLOY_WORKFLOW" --ref "$stg" -f env=staging …` dispatch
    (`promote.sh:83`);
  - the smoke call (`promote.sh:97-102`).

  This holds regardless of whether `PIPELINE_DEPLOY_CMD` / `PIPELINE_SMOKE_CMD` are set: capability
  off means no deploy step and no smoke step at all.

- **FR-11 (US-5, BR-7)** When deploy envs are off, **everything else in `promote.sh` is unchanged**:
  the branch/clean-tree guards, the `gate.sh` call and its exit handling, the merge to
  `BASE_BRANCH`, the `STAGING_BRANCH` ref update, the `vX.Y.Z` tag creation and push, the
  `releases.md` record, the `deploy-history.md` line, the commit, the branch push and the docs sync
  back to master. Same exit codes: `0` on success, `1` on any guard or gate failure.

- **FR-12 (US-1, BR-12)** When deploy envs are off, `DEPLOY_WORKFLOW`, `HEALTH_PATH` and the four
  `*_URL` keys are not required to hold meaningful values. `promote.sh` must not fail when they are
  empty strings. (The keys must still *exist* in `pipeline.env`; `promote.sh:20` does an indirect
  expansion `url="${!url_var}"` under `set -u`.)

- **FR-13 (US-5)** When deploy envs resolve **on** (including absent/unrecognised), `promote.sh`
  behaves exactly as today, including the existing `PIPELINE_DEPLOY_CMD` / `PIPELINE_SMOKE_CMD` /
  `PIPELINE_GH_CMD` / `PIPELINE_NO_PUSH` overrides used by the test suite.

- **FR-14 (US-9)** With deploy envs off, `promote.sh`'s progress line says so, e.g.
  `PROMOTE [SHI-5]: staging -> <sha> (no deploy: project has no deployable environments)`, so a
  skipped deploy reads as a setting rather than a silent omission.

### 1.4 `init.sh` / `/pipeline-init` — declare the shape at install time

- **FR-15 (US-6)** `scripts/init.sh` accepts two new flags, `--no-deploy-envs` and `--no-marketing`,
  alongside the existing `--project-dir|--name|--team-key|--profile|--force-tooling`. Unknown
  arguments still exit `1`. Arguments are still validated **before anything is copied** (CONTEXT.md
  high-risk area: no half-applied install).

- **FR-16 (US-6)** On a **fresh** install, `init.sh` writes the declared capability values into the
  newly created `scripts/pipeline/pipeline.env`: `PIPELINE_HAS_DEPLOY_ENVS="yes"|"no"` and
  `PIPELINE_HAS_MARKETING="yes"|"no"`. With no flags it writes `"yes"` for both — explicit, and equal
  to the default.

- **FR-17 (US-1, US-6, BR-12)** On a fresh install with `--no-deploy-envs`, `init.sh` does **not**
  create `scripts/deploy/{deploy,rollback,smoke}.sh` and does **not** create
  `.github/workflows/deploy.yml`. It **still** creates `.github/workflows/pipeline-gate.yml` (that is
  the gate check, not a deploy) and everything else it creates today.

- **FR-18 (US-1, US-6)** On a fresh install with `--no-deploy-envs`, the created `pipeline.env` keeps
  `DEPLOY_WORKFLOW`, `HEALTH_PATH`, `DEV_URL`, `QA_URL`, `STAGING_URL`, `PRODUCTION_URL` **present but
  empty**, with a comment saying the project has no deployable environments. No `__…__` placeholder
  may survive into a created file.

- **FR-19 (BR-13)** On a **re-run over an existing install**, `--no-deploy-envs` must **not** delete
  or modify `scripts/deploy/*`, `.github/workflows/deploy.yml` or the existing `pipeline.env`. They
  are project-owned. `init.sh` reports them as `kept` and prints an explicit instruction to the
  owner: set `PIPELINE_HAS_DEPLOY_ENVS="no"` in `scripts/pipeline/pipeline.env` by hand, and decide
  for themselves whether to delete the now-unused deploy files.

- **FR-20 (US-6)** `--force-tooling` must not resurrect `scripts/deploy/*` when `--no-deploy-envs` is
  given. With deploy envs on, `--force-tooling` behaves exactly as today.

- **FR-21 (US-6)** `init.sh` stays idempotent: a second run with the same arguments changes nothing
  except refreshing tooling files whose content differs.

- **FR-22 (US-6)** `commands/pipeline-init.md` instructs the assistant to ask the owner the two
  capability questions at install time and to pass the corresponding flags, and to record the answers
  in the new `docs/pipeline/CONTEXT.md`.

### 1.5 Orchestrator, personas and visibility

- **FR-23 (US-3)** `commands/ship.md` step 7 invokes `marketing-specialist` only when the project's
  marketing capability is on **and** the ticket is `User-facing: yes`. The literal stage order and
  the backticked persona names must be preserved (`tests/pipeline/test_config.sh:42-48` asserts the
  ordered sequence `…` `app-specialist` `…` `marketing-specialist` `…`).

- **FR-24 (US-3, BR-4)** `agents/product-owner.md` (and its `.claude/agents/` copy) states that
  `User-facing: yes|no` means only "does this change affect users" and no longer decides, by itself,
  whether a marketing persona runs.

- **FR-25 (US-2)** `agents/senior-engineer.md:33` ("hand off to the app-specialist, and to marketing
  if user-facing") and `agents/app-specialist.md:22` ("Once marketing is ready (or not needed)") are
  updated to the new rule: *project has marketing* **and** *ticket is user-facing*.

- **FR-26 (BR-11)** `agents/marketing-specialist.md` is **not** changed to know about project types.
  No product, person, project-type or vendor names enter any persona prompt or command file; the
  persona is skipped by configuration, above it. (`tests/pipeline/test_config.sh:19,41` enforces.)

- **FR-27 (US-9)** `scripts/pipeline/status.sh` prints the project's capabilities and which stages
  are disabled — see §3.2 for the exact output contract, including how an unrecognised raw value is
  surfaced.

- **FR-28 (US-9)** `/ship`'s owner-facing output (`commands/ship.md` "Output to the owner", and the
  go-live summary in step 8) says when marketing was skipped **by project configuration**, so
  "marketing did not run" is visibly a setting.

### 1.6 Docs and release

- **FR-29 (US-8)** The installing developer can learn the settings from the docs: `README.md`
  (scaffolding table + a line on the two settings), `docs/pipeline/TICKETS.md:67-75` ("What the gates
  require" — the production bullet), `docs/pipeline/BRANCHING.md:18,25`, `docs/pipeline/CLOUD.md`,
  `template/docs/pipeline/CONTEXT.md` (a place to record the project's shape in prose, per BR-2), and
  `template/RELEASE_CHECKLIST.md:32`. The `template/docs/pipeline/*` copies of TICKETS/BRANCHING/CLOUD
  must be updated in step with the repo's own copies (they are the files `init.sh:35` ships).

- **FR-30 (US-8, BR-10; amended 2026-09-19 by Q-4)** `.claude-plugin/plugin.json` `version` is
  exactly **`1.0.0`** for this release. The owner decided that this build ships as **v1.0.0**
  (Q-4), which supersedes BR-10's "bump the minor version" instruction for this release only; if the
  branch currently carries `1.1.0`, it is returned to `1.0.0`. `README.md` carries a **single**
  release-notes section headed `### v1.0.0` — there must be no `### v1.1.0` heading and no second
  `### v1.0.0` heading — and that one section describes both the first release's contents and this
  build's changes: the two new keys, their allowed values and defaults, that existing installs are
  unaffected until their owner adds them, the conditional production-gate marketing requirement, the
  skipped deploy/dispatch/smoke steps, and the two new `init.sh` / `/pipeline-init` flags. Any
  `v1.1.0` wording inside those bullets is corrected. At go-live the recorded `Version:` is
  `v1.0.0`, set by the owner's explicit override of `next-version.sh`'s proposal (see AC-35).

### 1.7 Dogfood this repo (BR-15, BR-16, Q-1 answered: new rules)

- **FR-31 (US-7)** This repo's `scripts/pipeline/pipeline.env` gets `PIPELINE_HAS_DEPLOY_ENVS="no"`
  and `PIPELINE_HAS_MARKETING="no"`, and the two `# n/a` apology comments on lines 5 and 10 are
  removed (the keys keep their values or become empty per FR-18's convention).

- **FR-32 (US-7)** `docs/pipeline/CONTEXT.md` is rewritten so it describes this project rather than
  apologising for the tooling: the "Environments" section (lines 41-49) drops "ignore 'build once,
  promote the image' in the generic docs" and instead states the declared capabilities plainly; the
  SHI-5 bullet under "Open strategic questions" (line 82-83) is removed, as it is now answered.

- **FR-33 (US-7)** `RELEASE_CHECKLIST.md` §5 loses "N/A — no image, no host" and §6 loses the
  hand-narrowed `User-facing` parenthetical (lines 35-37 and 43-45); both are rewritten as positive
  statements of what this project actually verifies.

- **FR-34 (US-7, BR-16, Q-1)** **Sequencing.** The FR-31 config flip must be committed on the SHI-5
  branch **before SHI-5 reaches its own dev gate (stage 6)**, so that every subsequent gate run for
  SHI-5 — dev, qa, staging and production — evaluates under the new rules and SHI-5's own production
  gate does not require a `marketing` ticket. See §6 for the rollout order.

---

## 2. Non-functional requirements

- **NFR-1 (fail closed — BR-8).** Every capability check is written so that the *strict* branch is
  the default path. No configuration value, malformed file or missing file may relax a requirement.
- **NFR-2 (blast radius — BR-6).** One `gate.sh`, one code path. No "library" fork, no second gate
  script, no new script in `scripts/pipeline/`. Adding or renaming a script there is a separate
  stop-and-ask (CONTEXT.md engineering rules). Budget: the production-stage block in `gate.sh` gains
  at most one condition; total `gate.sh` growth should stay under ~15 lines.
- **NFR-3 (write boundaries).** No change weakens `scripts/pipeline/hooks/allow-paths.sh` or
  `guard-merge.sh`, or any agent's `disallowedTools` frontmatter.
- **NFR-4 (no secrets — BR-12).** The new keys are booleans. A project that opts out of deployments
  ends with *less* secret surface (no `deploy.yml`, so no `DEPLOY_SSH_KEY` / `DEPLOY_HOST` /
  `DEPLOY_USER` / `DEPLOY_PATH` / `APP_URL` needed). Nothing new is written into a scaffolded repo
  beyond placeholder names.
- **NFR-5 (cross-platform — BR-14).** All new shell must work on Windows/Git-Bash and macOS BSD
  tooling. Specifically: no GNU-only `sed -i` without a backup suffix (`sed -i.bak … && rm -f *.bak`,
  as `init.sh:58-61` and `promote.sh:106` already do), no `grep -P`, no `readlink -f`, no bashisms
  that Git-Bash 4.x lacks, and no assumption about CRLF in `pipeline.env` — a value written by a
  Windows editor as `no\r` must still resolve to `no` (trimming per FR-2 covers `\r`).
- **NFR-6 (idempotency — CONTEXT.md).** `init.sh` stays idempotent and never overwrites a
  project-owned file: `docs/pipeline/CONTEXT.md`, `RELEASE_CHECKLIST.md`,
  `scripts/pipeline/pipeline.env`, `.github/workflows/*`, `scripts/deploy/*`,
  `.claude/settings.json`. Any new file introduced must be classified into tooling or project-owned.
- **NFR-7 (test baseline).** `bash tests/pipeline/run-all.sh` stays green and the total test count
  must not drop (README records 425). New behaviour lands in the existing suites —
  `test_config.sh`, `test_gate.sh`, `test_promote.sh`, `test_init.sh`, `test_intake_status.sh` — not
  in a new runner.
- **NFR-8 (performance/cost).** No new network calls, no new external dependency. For a project with
  deploy envs off, `promote.sh` makes *fewer* `gh` calls than today.
- **NFR-9 (untrusted input).** Capability values are read from a project-owned file and are only ever
  compared against a literal; they are never interpolated into a command, a path or a regex.
- **NFR-10 (persona agnosticism — BR-11).** No project, product, person, vendor or project-type name
  in `agents/*.md` or `commands/*.md`.

---

## 3. Script contracts (template's "API contract", mapped to this project)

### 3.1 `scripts/pipeline/gate.sh`

| Aspect | Today | After |
|---|---|---|
| Usage | `gate.sh <TICKET> <build\|dev\|qa\|staging\|production> [REF]` | unchanged |
| Exit 0 | prints `PIPELINE GATE [<T>/<stage>]: PASS (type=…, user-facing=…[, ref=…])`, then `DEPLOY_SHA=<sha>`, plus `VERSION=<tag>` for production | same, with the PASS line extended: `PASS (type=…, user-facing=…, marketing=<on\|off>, deploy-envs=<on\|off>[, ref=…])` |
| Exit 1 | usage error, or `PIPELINE GATE [<T>/<stage>]: <reason>` on stderr | unchanged — **no new failure mode, no new exit code** |
| stdout parsed by | `promote.sh:28-29` (`grep -vE '^(DEPLOY_SHA\|VERSION)='`, `sed -n 's/^DEPLOY_SHA=//p'`), `status.sh:11` | unchanged; the extra PASS text is on the human line only |
| Env inputs | `PIPELINE_ROOT`, `PIPELINE_DOCS_REF`, `PIPELINE_BASE_REF`, `PIPELINE_TICKET_REGEX` | unchanged. The two capability keys are **not** env inputs (FR-3) |

`gate.sh` must not emit anything new on **stderr** on a passing run: `status.sh:10` merges
`2>&1` and prints `head -1` of the output for a failing stage, so a stray warning line would
misreport the failure reason.

### 3.2 `scripts/pipeline/status.sh` (US-9)

Today (`status.sh:7-17`):

```
Pipeline gates for <TICKET>
  [x] build       sha <sha>
  [ ] dev         <first line of the failure>
  …
Next gate to clear: <stage>
```

After — one line added directly under the header, before the gate list:

```
Pipeline gates for <TICKET>
Project capabilities: deploy-envs=<on|off> marketing=<on|off>
  [x] build       sha <sha>
  …
Next gate to clear: <stage>
```

- When a capability is **off**, the line also names what that disables, e.g.
  `marketing=off (marketing-specialist and the production marketing requirement are skipped)` and
  `deploy-envs=off (deploy, dispatch and smoke steps are skipped; promotion still runs)`.
- When a raw value is present but unrecognised, the resolved value is shown with the raw value, e.g.
  `marketing=on (unrecognised value 'flase' — using the strict default)`. This is the only place a
  typo is surfaced, deliberately: it must not go to `gate.sh`'s stderr (§3.1).
- `status.sh` keeps exit code `0` regardless of gate outcomes, as today (`set -uo pipefail`, no `-e`).

### 3.3 `scripts/pipeline/promote.sh`

| Aspect | Today | After (deploy envs **off**) | After (deploy envs **on**) |
|---|---|---|---|
| Usage / args | `promote.sh <TICKET> <dev\|qa\|staging\|production>` | unchanged | unchanged |
| Pre-checks | branch ≠ base/staging; clean tree; `gate.sh` | unchanged | unchanged |
| dev | merge to `$BASE_BRANCH`, then `wait_for_deploy dev` | merge only | unchanged |
| qa | set `refs/heads/$STAGING_BRANCH`, then `wait_for_deploy qa` | ref update only | unchanged |
| staging | `gh workflow run "$DEPLOY_WORKFLOW" …` + `wait_for_deploy staging` | neither | unchanged |
| production | tag `vX.Y.Z`, push ref, `wait_for_deploy production` | tag + push ref only | unchanged |
| smoke | `${PIPELINE_SMOKE_CMD:-bash scripts/deploy/smoke.sh} "$url"` | not run | unchanged |
| records | `releases.md` line, `deploy-history.md` line, commit, push, docs sync to base | unchanged | unchanged |
| exit codes | `0` success / `1` any failure | unchanged | unchanged |

### 3.4 `scripts/init.sh` and `/pipeline-init`

| Aspect | Today | After |
|---|---|---|
| Flags | `--project-dir --name --team-key --profile --force-tooling` | `+ --no-deploy-envs --no-marketing` |
| Unknown flag | `exit 1` before copying | unchanged |
| Fresh install creates | … `scripts/deploy/{deploy,rollback,smoke}.sh`, `.github/workflows/{deploy,pipeline-gate}.yml` … | with `--no-deploy-envs`: **no** `scripts/deploy/*`, **no** `deploy.yml`; `pipeline-gate.yml` still created |
| `pipeline.env` written | 10 keys, placeholders filled | + the two capability keys; with `--no-deploy-envs`, `DEPLOY_WORKFLOW`/`HEALTH_PATH`/4 URLs written empty |
| Re-run over existing install | project-owned files reported `kept` | unchanged — **never** deletes deploy files, **never** edits an existing `pipeline.env`; prints the manual step (FR-19) |
| `--force-tooling` | refreshes `scripts/deploy/*` | same, except: no-op for `scripts/deploy/*` when `--no-deploy-envs` |
| Closing message | `Next: 1..4` | mentions the declared capabilities and, for an existing install, the manual `pipeline.env` edit |

### 3.5 `/ship` (`commands/ship.md`)

| Step | Today | After |
|---|---|---|
| Preamble | reads CONTEXT.md, TICKETS.md, BRANCHING.md, `pipeline.env` | unchanged; the two capability keys are read from `pipeline.env` here |
| 7. Staging | `app-specialist` (+ `marketing-specialist` if `User-facing: yes`) | `app-specialist` (+ `marketing-specialist` if the project has a marketing function **and** `User-facing: yes`) |
| 8. Go-live summary | lists "marketing launch ticket" | says "skipped — project has no marketing function" when the capability is off |
| Output to the owner | unchanged shape | a skipped stage is reported as skipped-by-configuration, never silently absent |

---

## 4. `gate.sh` pass/fail conditions — exact before/after (BR-9 / Q-2)

**This section is the specific diff the owner is asked to approve.** Nothing outside it changes a
pass/fail condition in `scripts/pipeline/gate.sh`.

### 4.1 Finding that narrows the change

`gate.sh` contains **no deploy-, smoke- or health-related pass/fail condition**. Its production-stage
checks are all *record* checks (a sha recorded in `releases.md`, an `Environment:` label in
`dev-check.md` / `qa-report.md` / `signoff.md`). The deploy/dispatch/smoke machinery that
`PIPELINE_HAS_DEPLOY_ENVS` governs lives entirely in `promote.sh` (§3.3) and `init.sh` (§3.4).

**Therefore exactly one pass/fail condition in `gate.sh` changes: the production stage's marketing
requirement, currently `scripts/pipeline/gate.sh:135`.**

### 4.2 The one changed condition

**BEFORE** — `scripts/pipeline/gate.sh:135`, inside the `# ---- production (tag) ----` block
(`if [ "$L" -ge 5 ]`), verbatim:

```bash
  if [ "$uf" = yes ]; then require_file marketing.md; expect marketing.md Status ready; [ -n "$(rows_where '$2=="marketing" && $5=="done"')" ] || fail "no completed marketing launch ticket"; fi
```

In words: *at the production gate, if `product.md` has `User-facing: yes`, then (a) `marketing.md`
must exist, (b) its `Status:` must be `ready`, and (c) `tickets.md` must contain at least one row of
kind `marketing` in state `done`. If `User-facing: no`, none of the three is required.*

**AFTER** — the same line, with one added conjunct (the engineer may format it differently; the
condition is what is being approved):

```bash
  if [ "$uf" = yes ] && [ "$has_marketing" = yes ]; then require_file marketing.md; expect marketing.md Status ready; [ -n "$(rows_where '$2=="marketing" && $5=="done"')" ] || fail "no completed marketing launch ticket"; fi
```

where `has_marketing` is resolved once, earlier in the file (near the existing
`regex="${PIPELINE_TICKET_REGEX:-…}"` at `gate.sh:26-27`, immediately after `pipeline.env` is
sourced), to `yes` unless the configured value is exactly `no` after trimming and lowercasing —
i.e. the strict value is the default and the `case` falls through to `yes`:

```bash
# capability resolution — strict (today's behaviour) unless the project explicitly opted out
case "$(printf '%s' "${PIPELINE_HAS_MARKETING:-yes}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
  no) has_marketing=no ;;
  *)  has_marketing=yes ;;
esac
```

The three checks inside the `if` are **unchanged**. The `[ "$uf" = yes ]` test is **unchanged** and
stays first. The failure message `"no completed marketing launch ticket"` is **unchanged**.

### 4.2.1 Complete truth table — exactly one cell moves

| `PIPELINE_HAS_MARKETING` in `pipeline.env` | `product.md` `User-facing` | marketing.md + `ready` + done launch ticket required? **BEFORE** | **AFTER** |
|---|---|---|---|
| key absent (every existing install) | `yes` | **required** | **required** — identical |
| key absent | `no` | not required | not required — identical |
| `"yes"` | `yes` | required | required |
| `"yes"` | `no` | not required | not required |
| **`"no"`** | **`yes`** | **required** | **NOT required ← the only change** |
| `"no"` | `no` | not required | not required |
| `""` (empty) | `yes` | required | **required** (fail closed) |
| `"false"` / `"0"` / `"off"` / `"maybe"` / any typo | `yes` | required | **required** (fail closed) |
| any value | `no` | not required | not required |

### 4.3 Conditions that explicitly do NOT change

Every one of these stays exactly as it is today. This list is part of the requirement, and the test
suite must keep asserting each of them (they all have existing coverage in `tests/pipeline/test_gate.sh`):

*Build stage (`gate.sh:85-95`)* — pipeline folder exists; `brief.md`; `product.md` with
`Status: approved`; `Type` ∈ `feature|bugfix|security|chore`; **`User-facing` ∈ `yes|no` (still
mandatory and still validated — it keeps its meaning, it is not removed)**; `research.md`
`Status: complete` for features; `requirements.md` `Status: approved`; `tickets.md` present; no
unknown kind/state rows; at least one `eng` row.

*Dev stage (`gate.sh:97-103`)* — `impl-notes.md` `Status: ready-for-dev`; every `eng` row `done` or
`wontfix`; no `defect` row `open`/`in-progress`/`reopened`; branch up to date with base.

*QA stage (`gate.sh:105-114`)* — `releases.md` `Dev:` sha resolvable and an ancestor; `dev-check.md`
`Result: pass`, `Environment: dev`, `Commit:` = the dev sha; no code change since the dev sha; the
dev sha is on the base branch.

*Staging stage (`gate.sh:116-124`)* — `releases.md` `QA:` = the dev sha; `qa-report.md`
`Result: pass`, `Environment: qa`, `Commit:` = the QA sha; every `dev`/`qa` defect `verified` or
`wontfix`.

*Production stage, everything except line 135 (`gate.sh:126-142`)* — `releases.md` `Staging:` = the
QA sha; `signoff.md` `Decision: approved`, `Environment: staging`, `Commit:` = the staging sha;
**every** defect `verified` or `wontfix`; no High-severity `wontfix`; `releases.md` `Go-live:` starts
with `approved`; `Version:` matches `^v[0-9]+\.[0-9]+\.[0-9]+$`; the tag does not already exist on a
different sha.

*Also unchanged* — the `Environment:` labels `dev`/`qa`/`staging` are still required in
`dev-check.md` / `qa-report.md` / `signoff.md` even for a project with no hosts: for such a project an
"environment" is the ref people install from (`master` / the `staging` branch / the version tag), and
the same sha still has to travel the same path (BR-7). `marketing` stays a valid ticket kind in
`tickets.md` for every project.

### 4.4 Blast-radius statement for the owner

- Projects that never add the key (**all existing installs**): zero behaviour change, proven by AC-12.
- Projects that set `PIPELINE_HAS_MARKETING="no"`: one requirement relaxed, at one stage, for
  user-facing tickets only. Nothing about sign-off, defects, go-live, versioning or the sha chain
  moves.
- A gate can only become *more* permissive by an explicit, project-owner-committed `no` in a
  project-owned file. Every other input, including a typo, keeps today's stricter behaviour.

---

## 5. Config schema changes (template's "data model" — there is no database)

`scripts/pipeline/pipeline.env` is a sourced Bash file, project-owned, **never overwritten** by
`init.sh` (`init.sh:25-28,48`). It is the only schema this project has.

| Key | New? | Type / allowed values | Default when absent | Written by `init.sh` on fresh install | Read by |
|---|---|---|---|---|---|
| `PIPELINE_HAS_DEPLOY_ENVS` | **new** | `yes` \| `no` (case-insensitive, trimmed; anything else = `yes`) | `yes` (today's behaviour) | `"yes"`, or `"no"` with `--no-deploy-envs` | `promote.sh`, `status.sh`, `/ship` |
| `PIPELINE_HAS_MARKETING` | **new** | `yes` \| `no` (same rules) | `yes` | `"yes"`, or `"no"` with `--no-marketing` | `gate.sh`, `status.sh`, `/ship` |
| `DEPLOY_WORKFLOW` | existing | filename | — | empty with `--no-deploy-envs` | `promote.sh` |
| `HEALTH_PATH` | existing | path | — | empty with `--no-deploy-envs` | `scripts/deploy/smoke.sh` |
| `DEV_URL` `QA_URL` `STAGING_URL` `PRODUCTION_URL` | existing | URL | — | empty with `--no-deploy-envs` | `promote.sh` |
| `PROJECT_NAME` `BASE_BRANCH` `STAGING_BRANCH` `TRACKER` `TRACKER_TEAM_KEY` `PIPELINE_TICKET_REGEX` | existing | — | — | unchanged | various |

**Migration: none, by design.** No existing install receives the new keys (BR-5); the scripts' own
defaults are the migration. A migration step is out of scope and tracked as SHI-12.

**Destructive changes: none.** No key is renamed or removed. No file is deleted by any script
(BR-13). `init.sh` gains the ability to *not create* two file groups on a fresh install; it never
gains the ability to remove them.

---

## 6. Operator-visible surface (template's "UI changes")

| Surface | Change | States / edge cases | Copy (exact where it matters) |
|---|---|---|---|
| `scripts/pipeline/status.sh` | new `Project capabilities:` line (§3.2) | capability on / off / unrecognised raw value | `Project capabilities: deploy-envs=off (deploy, dispatch and smoke steps are skipped; promotion still runs) marketing=off (marketing-specialist and the production marketing requirement are skipped)` |
| `gate.sh` PASS line | reports resolved capabilities | only on exit 0; failures unchanged | `PIPELINE GATE [SHI-5/production]: PASS (type=feature, user-facing=yes, marketing=off, deploy-envs=off)` |
| `promote.sh` progress line | says when no deploy happened | only when deploy envs off | `PROMOTE [SHI-5]: staging -> <sha> (no deploy: project has no deployable environments)` |
| `/pipeline-init` output | asks the two questions; reports what was skipped; for an existing install prints the manual step | fresh install vs re-run | re-run: `kept scripts/deploy/deploy.sh …` plus `This project declared no deployable environments. Existing deploy files were left untouched — set PIPELINE_HAS_DEPLOY_ENVS="no" in scripts/pipeline/pipeline.env yourself, and delete scripts/deploy/* and .github/workflows/deploy.yml if you no longer want them.` |
| `commands/ship.md` step 7 + owner output | marketing skip is stated as configuration | marketing on/off | `marketing: skipped — this project has no marketing function` |
| `docs/pipeline/CONTEXT.md` (this repo) | Environments section rewritten; SHI-5 open question removed (FR-32) | — | no "ignore what the generic docs say" phrasing may remain |
| `RELEASE_CHECKLIST.md` (this repo) | §5 and §6 rewritten (FR-33) | — | no `N/A — no image, no host`; no hand-narrowed `User-facing` parenthetical |
| `README.md`, `TICKETS.md`, `BRANCHING.md`, `CLOUD.md`, `template/…` | document the two settings and their defaults (FR-29) | — | `TICKETS.md` production bullet becomes: *for user-facing work in a project that has a marketing function, a `marketing` ticket is done* |

**Permissions matrix: N/A.** This project has no roles, users or authorisation surface. The nearest
equivalent — which persona may write which file — is unchanged and enforced by
`scripts/pipeline/hooks/allow-paths.sh` (NFR-3).

---

## 7. Acceptance criteria

Every AC is a test in `tests/pipeline/*`, runnable by `bash tests/pipeline/run-all.sh`.

### Capability resolution (FR-1, FR-2, FR-3)

- **AC-1 (FR-1, FR-2)** *Given* a fixture project whose `pipeline.env` sets
  `PIPELINE_HAS_MARKETING="no"`, *when* the production gate runs on a ticket with
  `User-facing: yes`, `marketing.md` absent and no `marketing` row, *then* the gate exits `0`.
- **AC-2 (FR-2, negative/fail-closed)** *Given* the same fixture with `PIPELINE_HAS_MARKETING=""`,
  *when* the production gate runs on the same ticket, *then* it exits `1` with
  `missing marketing.md`.
- **AC-3 (FR-2, FR-9, negative)** *Given* `PIPELINE_HAS_MARKETING="false"`, then `"0"`, then
  `"maybe"`, then `"Y"` (one case each), *when* the production gate runs on a user-facing ticket with
  no marketing evidence, *then* every one exits `1` — the permissive path is never taken by an
  unrecognised value.
- **AC-4 (FR-2)** *Given* `PIPELINE_HAS_MARKETING="  NO  "` and *given* a second fixture written with
  a trailing CR (`no\r`, simulating a Windows editor), *when* the production gate runs on a
  user-facing ticket with no marketing evidence, *then* both exit `0` (trim + lowercase, NFR-5).
- **AC-5 (FR-3, negative)** *Given* a fixture whose `pipeline.env` does **not** contain
  `PIPELINE_HAS_MARKETING`, *when* the production gate runs with `PIPELINE_HAS_MARKETING=no` exported
  in the environment on a user-facing ticket with no marketing evidence, *then* the gate still exits
  `1` — the environment cannot relax a project-level capability.
- **AC-6 (FR-5)** *Given* any fixture, *when* a gate passes, *then* stdout's PASS line contains
  `marketing=` and `deploy-envs=` with the resolved values, and `DEPLOY_SHA=<sha>` is still the
  parseable line `promote.sh` reads.

### Production gate, the changed condition (FR-6, FR-7)

- **AC-7 (FR-6)** *Given* `PIPELINE_HAS_MARKETING="no"` and a ticket with `User-facing: yes`, *when*
  the production gate runs with everything else satisfied, *then* it exits `0` without requiring
  `marketing.md` or a `marketing` ticket row.
- **AC-8 (FR-6, FR-7)** *Given* `PIPELINE_HAS_MARKETING="no"`, *when* the production gate runs on a
  ticket with an unverified defect, a High-severity `wontfix`, a missing `signoff.md`, an
  unapproved `Go-live`, or a malformed `Version`, *then* each still fails exactly as today — turning
  marketing off relaxes nothing else.
- **AC-9 (FR-6)** *Given* `PIPELINE_HAS_MARKETING="yes"` and `User-facing: yes`, *when* the
  production gate runs, *then* all three of today's marketing checks still apply, in today's order,
  with today's messages (`missing marketing.md`, `marketing.md Status is not 'ready'`,
  `no completed marketing launch ticket`).
- **AC-10 (FR-6)** *Given* `PIPELINE_HAS_MARKETING="yes"` and `User-facing: no`, *when* the
  production gate runs, *then* it passes without marketing evidence (unchanged from today).
- **AC-11 (FR-7)** *Given* any capability combination, *when* the `build`, `dev`, `qa` and `staging`
  gates run, *then* their outcomes are identical to today — the existing assertions in
  `tests/pipeline/test_gate.sh` for those four stages pass unmodified.

### Backwards compatibility — release blocker (FR-8, BR-5)

- **AC-12 (FR-8)** *Given* a fixture repo whose `scripts/pipeline/pipeline.env` contains **only the
  ten keys of the already-released 1.0.0 (commit `167445e`)** and neither new key — created by a new
  `tests/pipeline/lib.sh` helper (e.g. `legacy_env`) that rewrites the fixture's `pipeline.env` after
  `new_repo`, so the test still represents an install created *before this release* once `init.sh`
  starts writing the keys on fresh installs — *when*
  `gate.sh` is run for all five stages (`build`, `dev`, `qa`, `staging`, `production`) against
  `full_through` fixtures for **both** `User-facing: yes` and `User-facing: no`, *then* every exit
  code and every failure message is identical to the pre-change behaviour. The test must include the
  today-behaviour anchor cases explicitly:
  - user-facing + no `marketing.md` → exit `1`, message contains `missing marketing.md`;
  - user-facing + `marketing.md Status: ready` + no `done` marketing row → exit `1`, message contains
    `no completed marketing launch ticket`;
  - user-facing + full marketing evidence → exit `0`;
  - non-user-facing + no marketing evidence → exit `0`.

  This AC lives in `tests/pipeline/test_gate.sh` (and the `legacy_env` helper in `lib.sh`) and is
  **release-blocking**: a FAIL here blocks the production gate regardless of everything else.
- **AC-13 (FR-8)** *Given* the same legacy fixture, *when* `promote.sh` runs `dev`, `qa`, `staging`
  and `production` with the test overrides, *then* the deploy and smoke steps are invoked exactly as
  today (the existing `test_promote.sh` assertions pass unmodified).

### Promotion with no deployable environments (FR-10..FR-14)

- **AC-14 (FR-10)** *Given* a fixture with `PIPELINE_HAS_DEPLOY_ENVS="no"` and
  `PIPELINE_DEPLOY_CMD` pointing at a logging stub, *when* `promote.sh <T> dev|qa|staging|production`
  runs, *then* the stub log is **empty** — no deploy was attempted at any stage.
- **AC-15 (FR-10)** *Given* the same fixture with `PIPELINE_SMOKE_CMD=false` (a command that always
  fails), *when* `promote.sh <T> production` runs, *then* it exits `0` — smoke was not called. (With
  the capability on, the existing test asserts exit `1` here.)
- **AC-16 (FR-11)** *Given* the same fixture, *when* each promotion runs, *then* the sha still
  reaches `master`, the `staging` branch still points at the dev sha, the `vX.Y.Z` tag is still
  created on the staging sha, `releases.md` still records `Dev:`/`QA:`/`Staging:`/`Production:`,
  `deploy-history.md` still gains a line, and the records are still committed and synced to master.
- **AC-17 (FR-11, negative)** *Given* the same fixture with the ticket's `eng` rows still `open`,
  *when* `promote.sh <T> dev` runs, *then* it exits `1` at the gate and performs no git operation —
  turning deployments off does not weaken any guard.
- **AC-18 (FR-12)** *Given* a fixture with `PIPELINE_HAS_DEPLOY_ENVS="no"` whose `DEPLOY_WORKFLOW`,
  `HEALTH_PATH` and all four `*_URL` keys are the empty string, *when* every promotion runs, *then*
  none fails on an unset/empty variable (no `unbound variable`, no `smoke: … not healthy`).
- **AC-19 (FR-13, negative)** *Given* a fixture with the key **absent**, and one with
  `PIPELINE_HAS_DEPLOY_ENVS="maybe"`, *when* promotions run, *then* deploy and smoke are invoked, as
  today (fail closed applies to deployments too).
- **AC-20 (FR-14)** *Given* deploy envs off, *when* a promotion succeeds, *then* its output states
  that no deploy was performed and why.

### Install-time scaffolding (FR-15..FR-22, BR-13)

- **AC-21 (FR-15, FR-17)** *Given* an empty git repo, *when* `init.sh --project-dir P --name x
  --team-key X --no-deploy-envs` runs, *then* it exits `0`, and `P/scripts/deploy/`,
  `P/scripts/deploy/deploy.sh`, `P/scripts/deploy/rollback.sh`, `P/scripts/deploy/smoke.sh` and
  `P/.github/workflows/deploy.yml` do **not** exist, while `P/.github/workflows/pipeline-gate.yml`,
  `P/scripts/pipeline/gate.sh`, `P/docs/pipeline/CONTEXT.md` and `P/RELEASE_CHECKLIST.md` do.
- **AC-22 (FR-16)** *Given* the same run, *then* `P/scripts/pipeline/pipeline.env` contains
  `PIPELINE_HAS_DEPLOY_ENVS="no"` and `PIPELINE_HAS_MARKETING="yes"`; and with no flags at all, both
  are `"yes"`.
- **AC-23 (FR-18)** *Given* the `--no-deploy-envs` install, *then* `pipeline.env` still contains the
  keys `DEPLOY_WORKFLOW`, `HEALTH_PATH`, `DEV_URL`, `QA_URL`, `STAGING_URL`, `PRODUCTION_URL` with
  empty values, and the file contains no `__` placeholder.
- **AC-24 (FR-15, negative)** *Given* an argument list containing an unknown flag, *when* `init.sh`
  runs against a fresh repo, *then* it exits `1` and creates **no** files (validation before copying).
- **AC-25 (FR-19, BR-13)** *Given* a project already installed **with** deploy envs (so
  `scripts/deploy/*`, `.github/workflows/deploy.yml` and a `pipeline.env` exist, each with
  locally-edited content), *when* `init.sh --no-deploy-envs` is re-run over it, *then* all three are
  byte-identical afterwards, they are listed under `kept`, and the output tells the owner to set
  `PIPELINE_HAS_DEPLOY_ENVS="no"` by hand and that the deploy files were left for them to remove.
- **AC-26 (FR-20)** *Given* the same existing install, *when* `init.sh --no-deploy-envs
  --force-tooling` runs, *then* `scripts/deploy/*` is still not refreshed or created; *and given* an
  install without `--no-deploy-envs`, `--force-tooling` still refreshes them as today.
- **AC-27 (FR-21)** *Given* a `--no-deploy-envs --no-marketing` install, *when* `init.sh` is run a
  second time with the same arguments, *then* nothing is created or updated except tooling files
  whose content genuinely differs, and the installed project's own
  `bash tests/pipeline/run-all.sh` passes (as `test_init.sh:24` already asserts for the default
  shape).
- **AC-28 (FR-22)** *Given* `commands/pipeline-init.md`, *then* it names both flags and instructs the
  assistant to ask the owner the two capability questions and record the answers in `CONTEXT.md`.

### Orchestrator, personas, visibility (FR-23..FR-28)

- **AC-29 (FR-23, FR-25)** *Given* `commands/ship.md`, `agents/senior-engineer.md` and
  `agents/app-specialist.md`, *then* each states the marketing condition as *project has a marketing
  function* **and** *`User-facing: yes`*; and `tests/pipeline/test_config.sh`'s `/ship` stage-order
  assertion still passes.
- **AC-30 (FR-24)** *Given* `agents/product-owner.md`, *then* it states that `User-facing` means only
  whether the change affects users and does not decide whether a persona runs.
- **AC-31 (FR-26, negative)** *Given* every file in `agents/` and `commands/`, *then* none contains a
  product, person, vendor or project-type name, and `agents/marketing-specialist.md` contains no
  mention of project capabilities (the existing `test_config.sh` agnosticism assertions pass).
- **AC-32 (FR-27)** *Given* a project with both capabilities off, *when* `status.sh <TICKET>` runs,
  *then* its output contains `deploy-envs=off` and `marketing=off` with the explanation of what each
  disables, and the exit code is `0`.
- **AC-33 (FR-27, negative)** *Given* `PIPELINE_HAS_MARKETING="flase"`, *when* `status.sh` runs,
  *then* the output shows `marketing=on` and surfaces the unrecognised raw value; *and* `gate.sh`'s
  own stderr on a passing run is empty (so `status.sh`'s `head -1` failure reporting is unaffected).

### Docs, version, dogfood (FR-29..FR-34)

- **AC-34 (FR-29)** *Given* `README.md`, `docs/pipeline/TICKETS.md`, `BRANCHING.md`, `CLOUD.md` and
  their `template/docs/pipeline/` counterparts, *then* each describes the two settings, their
  defaults, and that an install without them behaves exactly as before; and the repo copy and the
  `template/` copy of TICKETS/BRANCHING/CLOUD say the same thing.
- **AC-35 (FR-30; amended 2026-09-19 by Q-4)** Three parts, all required:
  - *Given* the repo at the go-live commit, *when* `.claude-plugin/plugin.json` is read, *then*
    `version` is exactly `1.0.0`.
  - *Given* `README.md`, *when* its release-notes headings are counted, *then*
    `grep -c '^### v1.0.0' README.md` is `1` and `grep -c '^### v1.1.0' README.md` is `0` — one
    v1.0.0 section, no duplicate heading, no v1.1.0 heading — *and* that single section describes
    this build's changes (it mentions `PIPELINE_HAS_DEPLOY_ENVS`, `PIPELINE_HAS_MARKETING`, their
    `yes` default, that existing installs are unaffected until their owner adds a key, and the
    `--no-deploy-envs` / `--no-marketing` flags) as well as the first release's contents, with no
    `v1.1.0` wording left inside it.
  - *Given* that the repo has no tags, *when* the go-live step runs, *then* `next-version.sh` still
    proposes `v0.1.0` and that proposal is **overridden by the owner's explicit "go as v1.0.0"**, so
    `docs/pipeline/SHI-5/releases.md` records `Version: v1.0.0` — which satisfies the production
    gate's `^v[0-9]+\.[0-9]+\.[0-9]+$` check and matches `plugin.json`. *Negative:* a
    `releases.md` `Version:` that disagrees with `plugin.json`, or a README carrying a `### v1.1.0`
    heading, fails this AC.
- **AC-36 (FR-31, FR-32, FR-33)** *Given* this repo after the change, *then*:
  `grep -c 'n/a' scripts/pipeline/pipeline.env` is `0`;
  `RELEASE_CHECKLIST.md` contains no `N/A — no image, no host` and no
  `only for changes visible to the installing developer` parenthetical;
  `docs/pipeline/CONTEXT.md` contains no instruction to ignore the generic docs and no SHI-5 bullet
  under "Open strategic questions"; and `scripts/pipeline/pipeline.env` contains
  `PIPELINE_HAS_DEPLOY_ENVS="no"` and `PIPELINE_HAS_MARKETING="no"`. Success metric 1 (4 workarounds
  → 0) is measured by this AC.
- **AC-37 (FR-34, BR-16)** *Given* the SHI-5 branch at the point the dev gate is first run, *then*
  `scripts/pipeline/pipeline.env` already contains `PIPELINE_HAS_MARKETING="no"`; *when* SHI-5's own
  production gate later runs, *then* it passes without a `marketing` ticket and without
  `marketing.md`. (This is the dogfooding proof and closes Q-1.)
- **AC-38 (success metric 2)** *Given* a throwaway repo installed with
  `--no-deploy-envs --no-marketing`, *when* a ticket is walked through all five gates with the test
  fixtures, *then* it reaches a version tag with zero gate overrides and with `User-facing: yes` set
  honestly on a user-facing ticket.

---

## 8. Delivery notes

**New configuration keys.** `PIPELINE_HAS_DEPLOY_ENVS`, `PIPELINE_HAS_MARKETING`, both in
`scripts/pipeline/pipeline.env`, both optional, both defaulting to `yes` = today's behaviour. No
feature flags, no environment variables, no seed data, no secrets.

**Version (amended 2026-09-19, Q-4).** `.claude-plugin/plugin.json` `version` stays/returns to
**`1.0.0`**: the owner decided this build is released as **v1.0.0**, which supersedes BR-10's minor
bump and CONTEXT.md's minor-bump rule **for this release only**. Release notes live in `README.md`
as a **single** `### v1.0.0` section (no `### v1.1.0`, no duplicate `### v1.0.0`) and must still call
out the two keys, their defaults, and that no existing install changes behaviour until its owner adds
them. At go-live, `next-version.sh` proposes `v0.1.0` because the repo has no tags; the owner
overrides it with "go as v1.0.0" and `releases.md` records `Version: v1.0.0`.

**Rollout order (build stage).** The dependency chain is deliberate; `gate.sh`'s `dev` gate requires
every `eng` ticket `done`, so all of this lands before SHI-5's own dev merge:

```
ENG-1 (config schema + resolution)           ← unblocked, start here
   ├─► ENG-2 (gate.sh production condition)  ← BLOCKED until the owner approves §4 (Q-2/Q-3)
   │      └─► ENG-3 (backwards-compat proof, AC-12/AC-13) ← release blocker
   ├─► ENG-4 (promote.sh deploy/smoke conditional)
   ├─► ENG-5 (init.sh / pipeline-init scaffolding)
   └─► ENG-6 (ship.md, personas, status.sh visibility)
ENG-2 + ENG-4 + ENG-5 ─► ENG-7 (docs + version bump)
ENG-2 + ENG-4 ────────► ENG-8 (dogfood this repo)  ← LAST, and before the dev gate
```

**SHI-5's own gate (BR-16, Q-1 answered "new rules").** ENG-8 flips this repo's
`PIPELINE_HAS_MARKETING` to `no`. Because `pipeline.env` is read at gate time from the working tree,
the flip takes effect for every SHI-5 gate run after that commit. It must land in the build stage —
before stage 6 (dev). If ENG-8 were deferred, SHI-5's own production gate would still demand a
`marketing` ticket, stranding the release; if ENG-2 were deferred past ENG-8, the flip would simply
have no effect yet (safe, but the dogfood proof would be untested). Order: ENG-2, then ENG-8.

**Blocked work.** ENG-2 must not be started until the owner approves §4 in writing on SHI-5 (BR-9,
clarifications Q-2 → Q-3). Every other eng ticket is unblocked; ENG-1, ENG-4, ENG-5 and ENG-6 can
proceed in parallel with that approval.

**Decisions taken by the BA (not questions — recorded so the engineer does not re-litigate them):**

1. *Only the literal `no` turns a capability off* (FR-2). Accepting `false`/`0`/`off` as synonyms
   would widen the permissive surface for no benefit; BR-8 says only an explicit opt-out may relax.
2. *An unrecognised value does not fail the gate*, it falls back to strict and is surfaced by
   `status.sh` (§3.2). Hard-failing the gate on a config typo would block a release for a non-safety
   reason while the strict path is already safe, and a warning on `gate.sh`'s stderr would corrupt
   `status.sh`'s `head -1` failure reporting.
3. *`PIPELINE_HAS_DEPLOY_ENVS` changes nothing in `gate.sh`* (§4.1). The gate has no deploy-related
   condition to make conditional.
4. *This repo's own `.github/workflows/deploy.yml` is not deleted by this ticket.* It is
   project-owned, BR-13 says the owner decides, and BR-15's dogfood list names only `pipeline.env`,
   `CONTEXT.md` and `RELEASE_CHECKLIST.md`. Noted for the owner: that workflow triggers on pushes to
   `master`/`staging` and on `v*` tags and builds a Docker image this project does not have, so it is
   a candidate for deletion in a follow-up.
5. *Path correction.* product.md BR-11 and `docs/pipeline/CONTEXT.md` refer to `template/agents/*.md`;
   that directory does not exist. The persona files are `agents/*.md`, copied by `init.sh:34` into a
   consumer's `.claude/agents/`, with a mirror at this repo's own `.claude/agents/`. Requirements
   target the real paths, and **both copies must be edited together** (`test_init.sh:34` asserts they
   match).

**Test approach summary.** All new coverage lands in the existing suites: `test_config.sh`
(pipeline.env schema, agent/command wording, agnosticism), `test_gate.sh` (§4 conditions, AC-12
legacy-env matrix), `test_promote.sh` (deploy/smoke skipping), `test_init.sh` (scaffolding, BR-13
non-deletion, `--force-tooling`), `test_intake_status.sh` (`status.sh` output). One new helper in
`tests/pipeline/lib.sh` (`legacy_env`, and a fixture writer for capability values). Test count must
not drop below the current baseline (README: 425).

**Rollback (amended 2026-09-19, Q-4).** Nothing to migrate. If this release misbehaves, the rollback
target is the previously released build — commit `167445e`, which is also numbered 1.0.0 — so
**roll back by sha, not by version number**: the two builds carry the same version, which is a
consequence of the owner's Q-4 decision. Any project that has not added the keys is on identical
behaviour either way.
