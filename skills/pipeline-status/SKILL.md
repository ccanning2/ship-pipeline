---
name: pipeline-status
description: Show where a ticket is in the delivery pipeline and what it's waiting on. Use when asked where a ticket is, what it is blocked on, which sha is in each environment, whether the tracker has drifted from the ticket folder, or for a board of every ticket in flight.
argument-hint: "[TICKET-ID]"
---

# /pipeline-status

> The code host and tracker are reached through their CLIs. If you see unfamiliar placeholders or need to check which tools are used, see [CONNECTORS.md](../../CONNECTORS.md).

1. Run `bash scripts/pipeline/board.sh $ARGUMENTS` (the stages, who is busy with what, the environments) and `bash scripts/pipeline/status.sh $ARGUMENTS` (gate progress). With no ticket, run `bash scripts/pipeline/board.sh --all`.
2. Run `bash scripts/pipeline/enforcement.sh` (if it exists) for the enforcement mode: `host` means the code host requires the Pipeline Gate check; `local` means only the agent-side hook enforces the gates.
3. Read `docs/pipeline/<TICKET>/STATUS.md`, `releases.md` and `tickets.md`.
4. Read the parent ticket's Stage/Owner with `bash scripts/pipeline/tracker.sh view <TICKET>` (the ~~project tracker connector's tools only when it exits 3) and note any drift from `tickets.md`.
5. Reply with only:
   - the board, in a `text` code block;
   - **Next:** <the next gate and what it is blocked on, anything waiting on the owner, and drift from the tracker if any>;
   - **Enforcement:** <host, or say plainly that it is local hook only>.
