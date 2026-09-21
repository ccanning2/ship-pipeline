# Ticket handoff protocol (Linear / Jira)

**The tracker is the source of truth and the handoff medium.**
- Every persona picks work up from a ticket and hands it on by updating that ticket.
- The repo keeps a mirror (`docs/pipeline/<TICKET>/tickets.md`) so gates and CI can check state without calling the tracker.

Config lives in `scripts/pipeline/pipeline.env`: `TRACKER` (`linear` | `jira`), `TRACKER_TEAM_KEY` (ticket ids are `<TEAM KEY>-<number>`, matched through `PIPELINE_TICKET_REGEX` by `scripts/pipeline/ticket-id.sh`, the one definition the hook, the gate and both workflows share), and the two project capabilities `PIPELINE_HAS_DEPLOY_ENVS` and `PIPELINE_HAS_MARKETING` (`yes` | `no`, both defaulting to `yes`; only an explicit `no` turns one off, so a `pipeline.env` without them behaves exactly as before). Agents use whichever tracker connector tools the session has: the Linear connector by default, or the Atlassian connector for Jira. The human product owner is referred to as **the owner** (Owner label `owner`).

## Parent ticket
`/ship <TICKET>` takes only the ticket id. The parent ticket must already exist and contain the owner's requirement: title, description, and optionally attachments or links.

Two label groups track the parent. Each group allows one label at a time, so the labels always show where the ticket is and who holds it. They must be **single-select**: in Linear, create each as a label *group* (Settings → Labels → New group) and add its labels inside it; in Jira, use a single-select custom field. Plain labels would let a ticket carry two stages at once.

The full list of labels and workflow statuses the pipeline needs is `scripts/pipeline/tracker-schema.txt`. `/pipeline-doctor` compares it with the workspace and offers to create what is missing; nothing is created without the owner's yes.

| Label group | Labels |
|---|---|
| `Stage` | research, product, analysis, build, dev, qa, staging, go-live, production, done, on-hold |
| `Owner` | market-researcher, product-owner, business-analyst, engineer, qa, app-specialist, marketing, owner |

## Handoff = one comment + label change
Every handoff sets the parent's `Stage` and `Owner` labels and posts exactly one comment:

```
Handoff: <from persona> → <to persona>
Stage: <stage>
Summary: <1–3 lines>
Tickets: <linked ticket ids, or none>
Artifacts: docs/pipeline/<TICKET>/<file>.md @ <short sha>
Next: <what the receiver must do>
```

## Child tickets
Child tickets are always created as sub-issues of the parent and carry one **kind** label (`story`, `eng`, `defect`, `marketing` or `follow-up`).

| Kind | Created by | Purpose | States used |
|---|---|---|---|
| `story` | product-owner | Split user stories / scope | open → done |
| `eng` | business-analyst | Engineer-ready work items (FRs + ACs in the description) | open → in-progress → done |
| `defect` | qa-tester, app-specialist, marketing-specialist | A problem found in dev/qa/staging | open → in-progress → fixed → verified (or reopened / wontfix) |
| `marketing` | marketing-specialist | Launch/social content for the release | open → done |
| `follow-up` | product-owner, business-analyst | Out-of-scope ideas for later | open |

Rules:
- The **product owner and business analyst** may create and edit any ticket, and they are the only ones who change the parent's description or scope.
- **Reporters** (QA, app specialist, marketing) create `defect` tickets. A defect description holds:
  - steps to reproduce;
  - expected vs actual behaviour;
  - environment and sha;
  - severity (High, Medium or Low).
- The **engineer** moves `eng`/`defect` tickets to in-progress, then done/fixed, and comments with the fixing commit.
- **Only the reporter** marks a defect `verified` (after re-testing) or `reopened`. `wontfix` needs product-owner agreement in a comment; High-severity defects can't be `wontfix`.

State mapping to Linear workflow states: open/reopened → Todo, in-progress → In Progress, fixed → In Review, verified/done → Done, wontfix → Canceled. A new Linear team has no **In Review** status: add it (a *Started*-type status) before the first defect is fixed.

## Repo mirror: `tickets.md`
Whoever creates or changes a ticket also updates the matching row, in the same step:

```
| Ticket | Kind | Found-in | Severity | State | Owner | Title |
|---|---|---|---|---|---|---|
| REP-143 | eng | - | - | done | engineer | Badge embed endpoint |
| REP-150 | defect | qa | High | verified | qa | Vendor name not escaped in badge |
| REP-155 | marketing | - | - | done | marketing | Launch posts for badge |
```

Before each gate, the orchestrator re-reads the tracker and corrects any drift in the mirror.

## What the gates require (`scripts/pipeline/gate.sh`)
- **build:** at least one `eng` ticket exists.
- **dev (merge to `__BASE_BRANCH__`):** every `eng` ticket is done or wontfix, and no defect is open, in-progress or reopened.
- **staging:** every defect found in dev or qa is verified or wontfix.
- **qa (push to the `__STAGING_BRANCH__` branch):** dev self-check passed on the build.
- **production:**
  - every defect is verified or wontfix, and no wontfix is High severity;
  - for user-facing work **in a project that has a marketing function** (`PIPELINE_HAS_MARKETING` is
    anything but `no`), a `marketing` ticket is done. With `PIPELINE_HAS_MARKETING="no"` that
    requirement does not apply; nothing else about the gate changes.
