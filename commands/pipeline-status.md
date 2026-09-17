---
description: Show where a ticket is in the delivery pipeline and what it's waiting on.
argument-hint: <TICKET-ID>
---
1. Run `bash scripts/pipeline/status.sh $ARGUMENTS`.
2. Read `docs/pipeline/<TICKET>/STATUS.md`, `releases.md` and `tickets.md`.
3. If a tracker connector is available, read the parent ticket's Stage/Owner labels and note any drift from `tickets.md`.
4. Reply with only:
   - What was done: <stages completed; which sha runs in dev/qa/staging/production; open eng/defect tickets>
   - Impact: <next gate, what it's blocked on, and anything waiting on the owner>
