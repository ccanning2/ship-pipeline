# Ticket handoff protocol (Jira / Linear / GitHub Issues / GitLab issues)

**The tracker is the source of truth and the handoff medium.**
- Every persona picks work up from a ticket and hands it on by updating that ticket.
- The repo keeps a mirror (`docs/pipeline/<TICKET>/tickets.md`) so gates and CI can check state without calling the tracker.

Config lives in `scripts/pipeline/pipeline.env`: `TRACKER` (`jira` | `linear` | `github` | `gitlab` | `connector`), `TRACKER_TEAM_KEY` (ticket ids are `<TEAM KEY>-<number>`, matched through `PIPELINE_TICKET_REGEX` by `scripts/pipeline/ticket-id.sh`, the one definition the hook, the gate and both workflows share), and the project capability `PIPELINE_HAS_DEPLOY_ENVS` (`yes` | `no`, defaulting to `yes`). The human product owner is referred to as **the owner** (Owner label `human`; an Owner label may not repeat a Stage label or a group name, since Linear keeps label names unique per team).

## Reading and changing tickets: `scripts/pipeline/tracker.sh`
Every persona reaches the tracker through one CLI adapter, never through an MCP connector. `TRACKER` in `pipeline.env` picks the backend:

| `TRACKER` | Driven through | Stage / Owner | Children |
|---|---|---|---|
| `jira` | Atlassian CLI `acli`, plus Jira REST for fields and statuses | single-select fields `Stage` / `Owner` when the project's screens carry them, else labels `stage:<v>` / `owner:<v>` | sub-tasks |
| `linear` | Linear GraphQL API (personal API key) | label groups `Stage` / `Owner` | sub-issues |
| `github` | `gh` (this repository's issues; `KEY-12` is issue #12) | labels `stage:<v>` / `owner:<v>` | sub-issues |
| `gitlab` | `glab` (this project's issues; `KEY-12` is issue #12) | scoped labels `Stage::<v>` / `Owner::<v>` | linked issues |
| `connector` | the tracker's MCP connector tools (only when no CLI fits) | as the tracker allows | as the tracker allows |

```
bash scripts/pipeline/tracker.sh view <ID>                         # title, state, Stage, Owner, labels, description, children, comments
bash scripts/pipeline/tracker.sh children <ID>                     # ID | kind | state | title
bash scripts/pipeline/tracker.sh create <PARENT> <kind> '<title>' --body '<description>'   # prints the new id
bash scripts/pipeline/tracker.sh comment <ID> --body '<text>'      # or --body-file <file>
bash scripts/pipeline/tracker.sh describe <ID> --body-file <file>  # replace the description (PO / BA only)
bash scripts/pipeline/tracker.sh handoff <ID> <stage> <owner> --body '<handoff comment>'
bash scripts/pipeline/tracker.sh state <ID> <open|reopened|in-progress|fixed|verified|done|wontfix>
```
Put free text in single quotes; write a quote inside it as `'\''`. The product owner and business analyst run in plan mode: they may only `view` and `children`, enforced by `scripts/pipeline/hooks/allow-commands.sh`, and return their other ticket actions as a plan that `/ship` runs. Exit 3 means `TRACKER=connector`: use the connector's tools for that step. Sign-ins live outside the repository (`bash scripts/pipeline/connect.sh login`, once, by the owner).

## Parent ticket
`/ship <TICKET>` takes only the ticket id. The parent ticket must already exist and contain the owner's requirement: title, description, and optionally attachments or links.

**Teams** (`PIPELINE_TEAMS`, resolved by `scripts/pipeline/teams.sh`). A project selects which teams run: `analysis` (product owner + business analyst), `engineering`, `devops`, `qa` (qa-tester) and `signoff` (app specialist); `qa` and `signoff` bring `devops`. A ticket arrives at the first selected team, already taken through the earlier stages by another team:
- `engineering`: analysed; the description is the approved requirement, and the `eng` children (or the ticket itself) are the work.
- `devops`: built, on the ticket's branch.
- `qa` (only when the owner says the build is already on qa): already on qa.

At intake, `scripts/pipeline/handover.sh` records that upstream work in the ticket folder, as approved product and requirements records, `eng` rows, implementation notes, and the dev/qa records. A later stage whose team is not selected is the owner's (`Owner: human`): with `devops` selected, `/ship` waits for them and records their work with `handover.sh --by-owner build|qa|signoff`; without it, the run ends after the last selected team. The gates check the same records whoever did the work.

Two label groups track the parent. Each group allows one label at a time, so the labels always show where the ticket is and who holds it. They must be **single-select**: in Linear, create each as a label *group* (Settings → Labels → New group) and add its labels inside it; in Jira, use a single-select custom field. Plain labels would let a ticket carry two stages at once.

The full list of labels, fields and workflow statuses the pipeline needs is `scripts/pipeline/tracker-schema.txt`. `/pipeline-init` creates them (`tracker.sh setup`) with the owner's one upfront yes, and records in `scripts/pipeline/tracker.map` how each pipeline state maps onto this tracker's statuses. `/pipeline-doctor` reports anything missing later.

| Label group | Labels |
|---|---|
| `Stage` | product, analysis, build, dev, qa, staging, go-live, production, done, on-hold |
| `Owner` | product-owner, business-analyst, engineer, devops, qa-tester, app-specialist, human |

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
Child tickets are always created as sub-issues of the parent and carry one **kind** label (`story`, `eng`, `defect` or `follow-up`).

| Kind | Created by | Purpose | States used |
|---|---|---|---|
| `story` | product-owner | Split user stories / scope | open → done |
| `eng` | business-analyst | Engineer-ready work items (FRs + ACs in the description) | open → in-progress → done |
| `defect` | qa-tester, app-specialist | A problem found in dev/qa/staging | open → in-progress → fixed → verified (or reopened / wontfix) |
| `follow-up` | product-owner, business-analyst | Out-of-scope ideas for later | open |

Rules:
- The **product owner and business analyst** may create and edit any ticket, and they are the only ones who change the parent's description or scope.
- **Reporters** (QA, app specialist) create `defect` tickets. A defect description holds:
  - steps to reproduce;
  - expected vs actual behaviour;
  - environment and sha;
  - severity (High, Medium or Low).
- The **engineer** moves `eng`/`defect` tickets to in-progress, then done/fixed, and comments with the fixing commit.
- **Only the reporter** marks a defect `verified` (after re-testing) or `reopened`. `wontfix` needs product-owner agreement in a comment; High-severity defects can't be `wontfix`.

State mapping (`tracker.map`, written by `tracker.sh setup`; edit it to remap). Linear: open/reopened → Todo, in-progress → In Progress, fixed → In Review, verified/done → Done, wontfix → Canceled; setup adds **In Review** as a *Started* status. Jira: the project's statuses, with any that are missing mapped to the nearest one until the owner adds them to the workflow. GitHub/GitLab issues: open/closed, plus a `state:` label for in-progress and fixed.

## Repo mirror: `tickets.md`
Whoever creates or changes a ticket also updates the matching row, in the same step:

```
| Ticket | Kind | Found-in | Severity | State | Owner | Title |
|---|---|---|---|---|---|---|
| REP-143 | eng | - | - | done | engineer | Badge embed endpoint |
| REP-150 | defect | qa | High | verified | qa | Vendor name not escaped in badge |
```

Before each gate, the orchestrator re-reads the tracker and corrects any drift in the mirror.

## What the gates require (`scripts/pipeline/gate.sh`)
- **build:** at least one `eng` ticket exists.
- **dev (merge to `__BASE_BRANCH__`):** every `eng` ticket is done or wontfix, and no defect is open, in-progress or reopened.
- **staging:** every defect found in dev or qa is verified or wontfix.
- **qa (push to the `__STAGING_BRANCH__` branch):** devops' dev check passed on the build.
- **production:**
  - every defect is verified or wontfix, and no wontfix is High severity;
  - staging sign-off is approved, and the owner's Go-live and the Version are recorded.
