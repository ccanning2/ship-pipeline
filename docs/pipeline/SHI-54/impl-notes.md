# SHI-54 — Implementation notes

Status: ready-for-dev

The requirement (brief.md) is written for an LLM application. This repository is a Claude Code plugin: Bash pipeline
scripts plus Markdown agents and commands. The model calls, streaming and context windows belong to Claude Code, not
to this code. Each bullet is read below as it applies to the `/ship` orchestrator, the personas, the pipeline scripts
and the board. Nothing changes a gate's pass/fail condition, the branch/tag model, the write-boundary hooks, or any
script name or path. No agent file changed, so `agents/` and `.claude/agents/` stay identical. `template/` holds none
of the touched files.

## Bullet by bullet

### 1. Parallelize execution
- **Done: `scripts/pipeline/status.sh`.** It used to run five `gate.sh` checks and two `teams.sh` lookups one after
  another, and each start-up costs several processes (slow on Git Bash). They are read-only, so they now run side by
  side into a temporary directory and print in the usual order. `PIPELINE_STATUS_SERIAL=1` runs them in turn. The output
  is identical either way, and a test checks that.
- **Done: `tests/pipeline/run-all.sh`.** The files already ran in parallel. The runner now waits on each file in order
  (see bullet 3) rather than on all of them.
- **Done: `/ship` (`commands/ship.md`).** New standing rule "Read in parallel, act in turn": independent read-only
  lookups (`board.sh`, `status.sh`, `teams.sh --stages`, `tracker.sh view`/`children`, reading `D`) go out as parallel
  tool calls in one turn.
- **Not applicable: running personas or stages concurrently.** The stages are sequential gates, and "one persona at a
  time" is a safety rule: each stage's gate reads the previous stage's records, and the ticket's Owner label names one
  persona. Running personas in parallel would weaken the gates, so it is out of scope without an owner decision.

### 2. Implement caching
- **Done: per-call memo in `scripts/pipeline/lib/tracker-common.sh`** (`memo <key> <cmd...>`), used by the Linear
  adapter (`adapters/tracker-linear.sh`, installed here as `scripts/pipeline/tracker.sh`; the two stay identical) for
  the team and its labels. A `handoff` (Stage + Owner) used to fetch all workspace labels once per label group; it now
  fetches them once. The cache is a `mktemp -d` directory removed when the call exits. Nothing persists between calls,
  so it cannot go stale. A failed lookup is not cached (the error is still reported). `setup`, which creates labels,
  reads them fresh (`lin_labels_fetch`). `PIPELINE_TRACKER_NO_CACHE=1` turns the cache off.
- **Not applicable: the Jira, GitHub and GitLab adapters.** Their `set_group`/`state` read the issue's own labels,
  which change between one group and the next, so caching them would be wrong.
- **Not applicable: embedding lookups and static LLM responses.** The plugin makes no model or embedding calls of its
  own. Prompt caching is Claude Code's.

### 3. Stream tokens
- **Done: streamed test output.** `run-all.sh` prints each file's log in order as soon as it and every file before it
  have finished (it used to wait for all of them), with `[n/N] <file> passed|FAILED (p% of files done)` after each one
  and a `TOTAL: <passed> passed, <failed> failed` line at the end. Exit codes are unchanged.
- **Already in place: the live board.** `board.sh <T> --watch` / `--pane` redraws while the run goes on, and `/ship`
  already shows only the board after each stage.
- **Not applicable: token streaming between agents or to the user.** Claude Code streams model output. Personas hand
  off through the ticket and `D/`, not through a token stream the plugin could control.

### 4. Prune context
- **Done: `/ship` standing rule "Keep your context lean"** (`commands/ship.md`). The orchestrator briefs each persona
  with the ticket id, its mode, the branch and a one-line reason, never with pasted files, diffs, logs or an earlier
  persona's output. From a persona's result it keeps only the outcome, sha, test counts and questions. The detail stays
  in `D/` and on the ticket, where the next persona reads it. This builds on the existing "never relay" rule.
- **Not applicable: a summary agent or memory store.** The ticket folder `D/` and the tracker already are the
  pipeline's durable memory, and each persona already runs in its own subagent context. A separate summary persona
  would add a seventh agent (an agent-name change for every installed project) for no gain.

### 5. Status %
- **Done: `board.sh <TICKET>`** prints an estimated progress line under the stages:
  `progress [######..............]  31%  2 of 8 stages done or skipped, 1 under way`. A stage done or skipped counts
  in full, the one under way (or blocked/on-hold) counts as half. It is computed in the shell loop that already draws
  the rows, so it adds no process (the board stays light for `--watch`).
- **Done: `board.sh --all`** ends each ticket's line with the same percentage.
- **Done: `status.sh <TICKET>`** prints `Gates cleared: n of 5 (p%)` before "Next gate to clear".
- **Done: `run-all.sh`** shows the share of test files done (bullet 3).
- Per-step time estimates are not given: stage durations depend on the owner and the tracker, so a percentage of
  stages is the honest estimate.

## Files changed
- `scripts/pipeline/lib/tracker-common.sh`: `memo`/`memo_init` and a header note on the cache.
- `scripts/pipeline/adapters/tracker-linear.sh` and `scripts/pipeline/tracker.sh` (same content): memoised
  `lin_team`/`lin_labels`, `setup` reads fresh.
- `scripts/pipeline/status.sh`: parallel reads, `PIPELINE_STATUS_SERIAL`, gates-cleared line.
- `scripts/pipeline/board.sh`: progress line, `--all` percentage, header text.
- `commands/ship.md`: board description, the two new standing rules.
- `tests/pipeline/run-all.sh`: streamed in-order output, `[n/N]` progress, TOTAL line.
- Tests: `test_adapters.sh` (Linear through a fake API: labels read once per call, not between calls, NO_CACHE,
  state, API down is still an error); `test_intake_status.sh` (gates cleared 80% and 100%, serial equals parallel,
  board progress line, `--all` percentage); `test_config.sh` and `test_init.sh` (AC-50 now checks plugin.json is 3.2.0 or later and that the changelog opens with its version).
- Docs: `README.md` (board example, `--all`, test runner), `CHANGELOG.md` v3.3.0, `.claude-plugin/plugin.json`
  3.3.0 (proposed: additive feature, no tooling path/agent/template rename).

## Tests
`bash tests/pipeline/run-all.sh`: 1948 passed, 0 failed (baseline 1930 passed on v3.2.0).

## How to check it on dev
Install the plugin from `master` into a throwaway git repo and `/pipeline-init` it (Linear not needed for most of it):
1. `bash scripts/pipeline/board.sh <T>` on a ticket with some stages done: the `progress [...] NN%` line appears under
   the stages; `board.sh --all` ends each line with a percentage.
2. `bash scripts/pipeline/status.sh <T>`: same gate lines as before plus `Gates cleared: n of 5 (p%)`; with
   `PIPELINE_STATUS_SERIAL=1` the output is identical.
3. In this repo: `bash tests/pipeline/run-all.sh` streams `[n/N] ...` lines and ends with `TOTAL:` and
   `ALL PIPELINE TESTS PASSED`.
4. With a Linear workspace (optional): `tracker.sh handoff <T> dev devops --body '...'` still sets Stage and Owner and
   posts the comment.
5. `/ship` text: `commands/ship.md` has "Keep your context lean" and "Read in parallel, act in turn" under Standing rules.

## For devops
- No CI, deploy or infra file changes. The version tag cut at go-live should match `plugin.json` (3.3.0 proposed).
