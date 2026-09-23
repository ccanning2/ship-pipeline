---
description: Show where a ticket is in the delivery pipeline and what it's waiting on.
argument-hint: <TICKET-ID>
---
1. Run `bash scripts/pipeline/board.sh $ARGUMENTS` (the stages, who is busy with what, the environments) and `bash scripts/pipeline/status.sh $ARGUMENTS` (gate progress). With no ticket, run `bash scripts/pipeline/board.sh --all`.
2. Run `bash scripts/pipeline/enforcement.sh` (if it exists) for the enforcement mode: `host` means the code host requires the Pipeline Gate check; `local` means only the agent-side hook enforces the gates.
3. Read `docs/pipeline/<TICKET>/STATUS.md`, `releases.md` and `tickets.md`.
4. Read the parent ticket's Stage/Owner with `bash scripts/pipeline/tracker.sh view <TICKET>` (the connector's tools only when it exits 3) and note any drift from `tickets.md`.
5. Reply with only:
   - the board, in a `text` code block;
   - **Next:** <the next gate and what it is blocked on, anything waiting on the owner, and drift from the tracker if any>;
   - **Enforcement:** <host, or say plainly that it is local hook only>.
