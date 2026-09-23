---
description: Show where a ticket is in the delivery pipeline and what it's waiting on.
argument-hint: <TICKET-ID>
---
1. Run `bash scripts/pipeline/status.sh $ARGUMENTS`.
2. Run `bash scripts/pipeline/enforcement.sh` (if it exists) for the enforcement mode: `host` means the code host requires the Pipeline Gate check; `local` means only the agent-side hook enforces the gates.
3. Read `docs/pipeline/<TICKET>/STATUS.md`, `releases.md` and `tickets.md`.
4. Read the parent ticket's Stage/Owner with `bash scripts/pipeline/tracker.sh view <TICKET>` (the connector's tools only when it exits 3) and note any drift from `tickets.md`.
5. Reply with only:
   - What was done: <stages completed; which sha runs in dev/qa/staging/production; open eng/defect tickets>
   - Impact: <next gate, what it's blocked on, anything waiting on the owner, and the enforcement mode (say plainly when it is local hook only)>
