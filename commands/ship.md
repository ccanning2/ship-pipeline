---
description: Run the delivery pipeline for one tracker ticket — research → product owner → business analyst → engineer → dev (master) → QA (staging branch) → staging → go-live → production (version tag). Tickets are the handoffs. Resumable.
argument-hint: <TICKET-ID>
---
You are the pipeline orchestrator for ticket `$ARGUMENTS` in THIS project.

- Take only the first token and uppercase it: that is the ticket id. Ignore any other text.
- Call the ticket folder `D = docs/pipeline/<TICKET>/`.
- If `scripts/pipeline/gate.sh` or `docs/pipeline/CONTEXT.md` is missing, stop and tell the owner to run `/pipeline-init` first.
- Read `docs/pipeline/CONTEXT.md`, `docs/pipeline/TICKETS.md`, `docs/pipeline/BRANCHING.md` and `scripts/pipeline/pipeline.env` before anything else. The tracker ticket is the source of truth and the handoff medium.

## Standing rules
- **Tracker access.** Use the tracker connector tools in this session (Linear, or Jira if `TRACKER=jira`). If none is available, stop and ask the owner to enable it.
- **One persona at a time.** Before each stage: re-read the parent ticket and its children, correct any drift in `D/tickets.md`, confirm the parent's `Owner` label names the persona you're about to run. After each stage: confirm the handoff comment and labels, update `D/STATUS.md`, commit and push the ticket branch.
- **Cloud sessions** (`CLAUDE_CODE_REMOTE=true`): stay on the session branch; write the ticket id to `.claude/.pipeline-ticket`; open a draft PR to `master` titled `<TICKET>: <ticket title>` right after intake.
- **Rework limit.** A code change after the dev deploy always goes back through dev → qa → staging. After 3 rework loops, set Owner: owner, Stage: on-hold, and stop.
- **Waiting on the owner.** Whenever a stage hands off to the human owner, stop and say exactly what's needed in one message. On resume, record the answer and continue.

## 0. Resume or intake
- **Resume** if `D/STATUS.md` exists: continue from the first stage not `done`/`skipped` (`bash scripts/pipeline/status.sh <TICKET>` shows gate progress).
- **Intake** otherwise:
  1. Read the ticket from the tracker. If it doesn't exist or its description is empty, stop and ask the owner to write the requirement there.
  2. Locally: create `feature/<TICKET>-<slug>` from an up-to-date `master`. In the cloud: use the session branch.
  3. Pipe the ticket's title, description and attachment/link list into `bash scripts/pipeline/intake.sh <TICKET> - "<ticket url>"`.
  4. Create `D/tickets.md` from the template.
  5. Set Stage: research, Owner: market-researcher on the parent and post the orchestrator's handoff comment.

## 1. Research — `market-researcher`
Skip only when the ticket is labelled Bug, Security or Chore (hand straight to the product owner). If it recommends build-later or drop, stop.

## 2. Product — `product-owner` (mode A)
`blocked` → relay questions to the owner. `rejected` → stop.

## 3. Analysis — `business-analyst` ⇄ `product-owner`
The BA writes requirements.md and creates the `eng` tickets. While open `To: PO` questions exist, run `product-owner` (mode B) then the BA again (max 3 rounds). Open `To: Owner` questions → ask them all in one message and stop. Continue only when `gate.sh <TICKET> build` passes.

## 4. Build — `senior-engineer` mode **build**
Works the `eng` tickets, or in rework the open `defect` tickets.

## 5. Dev — `senior-engineer` mode **promote-dev**
Merges to `master` (deploys dev, builds the image), self-checks on dev, writes `dev-check.md`. Fail → step 4 (rework loop). Pass → promotes to QA (push to `staging` branch) and hands off to qa.

## 6. QA — `qa-tester`
Defects raised → engineer, step 4. Pass → `senior-engineer` mode **promote-staging**.

## 7. Staging — `app-specialist` (+ `marketing-specialist` if User-facing: yes)
Any defects → step 4 (a fix passes through dev and QA again). Continue only when sign-off is approved and marketing is ready or not needed.

## 8. Go-live — owner
1. Propose the version: `bash scripts/pipeline/next-version.sh <TICKET>`.
2. Set Stage: go-live, Owner: owner, and send ONE summary: ticket and children; sha; proposed version; test counts; defects found/verified; sign-off; marketing launch ticket; rollback plan (previous version tag).
3. Ask: **"Release `<version>` (sha `<sha>`) to production? (go / no-go / go as vX.Y.Z)"** and stop.
4. On go: write `Version: <version>` and `Go-live: approved by <owner> <ISO timestamp>` to `D/releases.md`, comment the same on the ticket, commit, hand off to the engineer. On no-go: record the reason, Stage: on-hold, stop. Never write Go-live without an explicit go in this conversation.

## 9. Production — `senior-engineer` mode **promote-production**
Tags the sha, waits for the deploy, verifies, rolls back on failure. Ends with the parent at Stage: done / Done and a release summary (version, image tag, tickets) reminding the owner the launch content is ready to publish.

## Usage-limit safety
Before each stage, if the session may be near its usage limit: stop cleanly, make sure `D/STATUS.md` and the ticket labels are accurate, commit and push, and tell the owner to run `/ship <TICKET>` to resume.

## Output to the owner
Only this:
- What was done: <one bullet per stage run this session, with outcome and ticket ids>
- Impact: <current environment/sha/version, open defect tickets, what the owner must do next>
