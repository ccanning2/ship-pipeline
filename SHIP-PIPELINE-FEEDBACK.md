# ship-pipeline: suggested changes for the next release

Collected while installing and configuring the pipeline in `price-compare` (2026-09-21): a repo whose
trunk is `main`, that was migrating from GitLab to GitHub, has no deployed environments, and tracks work
in Linear. Each item says what happened, the evidence, and a suggested fix.

**Evidence tags:** *Verified* = seen directly in this repo or its tool output. *Inferred* = a reasonable
reading of what was seen, worth confirming before acting on it.

## Summary

| # | Gap | Impact | Effort |
|---|---|---|---|
| 1 | No readiness check (`/pipeline-doctor`) | Every gap below was found by hand | M |
| 2 | Base branch hardcoded to `master` in agents, docs and workflows | Agents run commands that fail | S |
| 3 | Ticket regex too broad, and inconsistent across three places | False "ungated promotion" blocks; PR gate mismatch | S |
| 4 | Guard hook has no route for legitimate non-ticket pushes | First push of a repo is blocked with no way forward | M |
| 5 | Tracker workspace is never checked or prepared | `/ship` would fail on first handoff | M |
| 6 | Docs claim branch protection that a free private repo can't have | Enforcement is silently weaker than documented | S |
| 7 | Installer leaves stray files and copies a header into `.gitignore` | Repo noise | S |
| 8 | `deploy.yml` fails on every push when there are no deploy environments | Red CI from day one | S |
| 9 | Remote and host assumptions: `origin` hardcoded, no history check | Unrelated-history push, wrong remote | S |
| 10 | Ticket-required PR gate blocks infra PRs and reruns the self-test every time | Friction and CI cost | S |
| 11 | Plugin-owned agent files are edited in place | Local fixes may be lost on update | M |

---

## 1. Add a readiness check: `/pipeline-doctor`

**What happened.** Getting from "installed" to "ready for `/ship`" needed a long manual audit, and it
surfaced most of the items below. `/pipeline-init` reports success without checking any of it, and
`/pipeline-status` is per-ticket, so nothing answers "is this repo ready?".

**Suggested fix.** A read-only command, also run at the end of `/pipeline-init`, that reports pass/warn/fail for:

- Files present, scripts executable, `tests/pipeline/run-all.sh` passing.
- `pipeline.env` sanity:
  - `BASE_BRANCH` and `STAGING_BRANCH` exist on the remote.
  - `PIPELINE_TICKET_REGEX` is narrower than "any word-number".
  - `TRACKER_TEAM_KEY` is set.
- Git:
  - The remote named `origin` is the code host.
  - `origin/<BASE_BRANCH>` shares history with local (a README-only remote is the classic trap; this install hit it, see 9).
  - The staging branch is an ancestor of, or equal to, a base-branch sha.
- Host: `gh auth status`, and whether branch protection is available at all (see 6).
- Tracker: connector reachable, team key resolves, required labels and statuses exist (see 5).
- Hooks: `guard-merge.sh` is wired in `.claude/settings.json`.
- Stale literals: grep installed files for `master` when `BASE_BRANCH` is not `master` (see 2).

*Verified* that all of these were checked by hand in this install. The output would double as the
"what still needs doing" list.

## 2. Base branch is hardcoded to `master`

**What happened.** `pipeline.env` has a `BASE_BRANCH` key and the scripts read it, but the rest of the
install ignores it. *Verified* in this repo (trunk is `main`):

- Agent prompts:
  - `app-specialist.md:11` and `qa-tester.md:17` say `git diff origin/master...HEAD`.
  - `senior-engineer.md:16` and `:20` say `git merge --no-edit origin/master`.
  - These are literal commands an agent will run, and `origin/master` does not exist.
- Docs and templates: `docs/pipeline/BRANCHING.md`, `TICKETS.md` and `_templates/STATUS.md` are written around `master`.
- Comments: `gate.sh:9` says CI uses `origin/master`.
- Workflows: the generated workflows targeted `master` and were retargeted by hand (`CONTEXT.md` records this).
- Skill text: the `ship` skill description says "dev (master)".
- Scripts: `gate.sh:78`, `promote.sh:29` and `guard-merge.sh:19` default to `${BASE_BRANCH:-master}`.
- Tests: `tests/pipeline/lib.sh` says every assertion "is written against master", and had to be patched so a
  hosting project's `BASE_BRANCH` doesn't leak into the fixtures.

**Suggested fix.**

- `/pipeline-init` detects the trunk (`git symbolic-ref refs/remotes/origin/HEAD`, else the current branch)
  and asks the user to confirm it.
- Templates use a placeholder, for example `{{BASE_BRANCH}}`, substituted at install time, so workflows,
  docs and agent prompts come out correct.
- For text agents read at run time, say "the base branch (`BASE_BRANCH` in `pipeline.env`)" or call one
  helper, `scripts/pipeline/base-ref.sh`, that prints `origin/<BASE_BRANCH>`.
- Script defaults resolve from `origin/HEAD` instead of assuming `master`.
- Add a test: install into a fixture whose trunk is `main` and assert no `master` literal remains outside
  intentional fixtures. The doctor check in 1 can reuse that grep.

## 3. Ticket regex: too broad, and defined in three places

**What happened.**

- *Verified.* The shipped default `PIPELINE_TICKET_REGEX` (`[A-Z][A-Z0-9]+-[0-9]+`, case-insensitive) also matches runner
  labels and image tags such as `macos-14` or `v1.45.0-jammy`. `guard-merge.sh` then blocked ordinary
  shell commands as ungated production promotions (recorded in commit `b2ca9b4`).
- *Verified.* `.github/workflows/pipeline-gate.yml:21` hardcodes its own copy of the regex
  (`grep -oiE '[A-Z][A-Z0-9]+-[0-9]+'`), so narrowing `PIPELINE_TICKET_REGEX` in `pipeline.env` does not
  affect the PR gate. A branch such as `fix/utf-8-bug` yields "ticket" `UTF-8`.
- *Verified.* The test fixtures use `REP-nnn` ids, so `tests/pipeline/lib.sh` had to be patched to stop a
  project's narrowed regex leaking into them.

**Suggested fix.**

- One source of truth: default the regex to `${TRACKER_TEAM_KEY}-[0-9]+` when the key is set.
- `/pipeline-init` asks for the team key, so the broad default is only a fallback.
- The workflow sources `pipeline.env` instead of embedding its own pattern.
- Fixtures set their own regex and team key explicitly and never read the host project's.

## 4. The guard hook has no route for legitimate non-ticket pushes

**What happened.** *Verified.* Pushing this repo's history to a new `origin` (an authorized, one-off
bootstrap step) was blocked with `no ticket id found in the command, branch 'main'…Run /ship <TICKET>`.
The same class of action recurs: the initial push, the install commit itself, a CI migration, a
dependency bump, a config change. None has a ticket, and there is no documented way through.
`docs/GITHUB-MIGRATION.md` also records that the hook scans the whole command text, so incidental strings
trip it.

**Suggested fix.**

- Make the block message actionable: say the user can run the command themselves in their own terminal
  (the hook only gates agent tool calls), and how to create or attach a ticket.
- Document a sanctioned path for repo maintenance, for example a reserved infrastructure ticket
  convention (`<KEY>-0`, or a tracker label such as `infra`) that the gate treats as
  "no stage gates, still needs a reviewer".
- **Do not** offer an env-var bypass the agent can set itself: it would defeat the gate. If any override
  exists it must be something only the human can set.
- Parse the git subcommand and target ref (`push`, `merge`, `tag`, `--force*`) rather than scanning the
  full command string, so `echo`, `tail` and pipes in a compound command don't matter.

*Inferred:* the substring scan is why the compound command was matched; the block reason itself was
"no ticket id".

## 5. The tracker workspace is never checked or prepared

**What happened.** *Verified* against the Linear workspace with `TRACKER=linear` and `TRACKER_TEAM_KEY=PRI`:

| The protocol needs (`TICKETS.md`) | Found |
|---|---|
| `Stage` label group (11 labels) | Missing |
| `Owner` label group (8 labels) | Missing |
| Kind labels `story`, `eng`, `defect`, `marketing`, `follow-up` | Missing |
| Status "In Review" (the `fixed` mapping) | Missing (team has Backlog, Todo, In Progress, Done, Canceled, Duplicate) |
| Parent ticket | None; the team had no issues |

The team existed and the connector worked, but the first handoff would have failed.

**Suggested fix.**

- Extend `/pipeline-init` (or the doctor) with a tracker step that lists what exists and offers to create
  the missing label groups, kind labels and status, after confirming with the user. That is a
  persistent change to a shared workspace, so it should never be silent.
- Ship the label and status list as data (one file), so the doctor, the docs and the `pipeline-status`
  output share one definition.
- Say in `TICKETS.md` that `Stage` and `Owner` must be single-select (label groups) and how to make them so.
- *Inferred:* Linear connector tool names are opaque (`mcp__<uuid>__…`), so "use whichever tracker
  connector the session has" is unverifiable until first use. The doctor should run one harmless read
  call and report the result.

## 6. Documented branch protection may not be available

**What happened.** *Verified.* `BRANCHING.md` states "`master` and `staging` are protected; the Pipeline Gate
check is required on PRs to both." On a private repo on GitHub's free plan the API returns HTTP 403
("Upgrade to GitHub Pro or make this repository public") for both branch protection and rulesets, so the
required checks cannot be configured. The install gives no warning. This repo chose to rely on the local
hook alone.

**Suggested fix.**

- The doctor probes `gh api repos/{repo}/branches/{base}/protection` and `…/rulesets`; on 403, it reports
  "enforcement mode: local hook only" with the consequence stated (the hook gates agent sessions only;
  a human or another tool can push past it).
- `BRANCHING.md` gets a conditional line for both modes instead of a flat claim.
- `/pipeline-status` prints the enforcement mode so it is never a surprise.

## 7. Installer hygiene

**What happened.** *Verified.*

- `.gitignore.pipeline` (its content is "Append to .gitignore" plus two ignore lines) was committed as a
  file at the repo root, and the same lines were also appended to `.gitignore`.
- The instruction header "`# Append to .gitignore`" was copied verbatim into `.gitignore` (line 105).

**Suggested fix.** Append only the ignore entries, idempotently (skip lines already present), with a
sensible comment such as `# ship-pipeline`. Do not commit or leave the `.pipeline` file behind.

## 8. `deploy.yml` fails on every push when nothing is deployed

**What happened.** *Verified.* The generated `deploy.yml` runs on every push to the base branch. With no
environments it would fail every time; this repo had to gate it behind a repository variable
(`vars.PIPELINE_DEPLOY_ENABLED == 'true'`) by hand (commit `b2ca9b4`). `PIPELINE_HAS_DEPLOY_ENVS="no"`
makes `promote.sh` skip deploys, but the workflow still ships enabled.

**Suggested fix.**

- `/pipeline-init` asks whether deployable environments exist, sets `PIPELINE_HAS_DEPLOY_ENVS`, and either
  omits `deploy.yml` or installs it already gated behind `PIPELINE_DEPLOY_ENABLED`.
- Cover the same "no environments" mode in the gate and status output, not only in `promote.sh`.

## 9. Remote and host assumptions

**What happened.**

- *Verified.* The install ran while `origin` did not yet exist as the code host. The GitHub `origin` was
  later created with a README-only "Initial commit" that shared no history with the local repo (151 local
  commits versus 1 remote). Everything the pipeline does (PR merges, gate workflows, `promote.sh`) works
  against `origin`, so this had to be resolved by a force push before anything could run.
- *Verified.* `promote.sh:52` fetches and merges `origin/$base` with the remote name hardcoded; this repo also
  has a `gitlab` remote.
- `BRANCHING.md` assumes `ghcr.io/<repo>` images and GitHub REST merges; the install ran in a repo whose
  CI, registry and remote were still GitLab, and nothing warned about that mismatch.

**Suggested fix.**

- Add `PIPELINE_REMOTE` (default `origin`) to `pipeline.env` and use it everywhere.
- The doctor checks that the remote exists, points at the expected host, and shares history with local.
- Say plainly in the README which hosts and CI systems are supported, so a GitLab-origin repo knows to
  migrate first.

## 10. The PR gate requires a ticket for every PR and reruns the self-test each time

**What happened.** *Verified.* `pipeline-gate.yml` fails any PR into the base or staging branch unless the
branch name or PR title contains a ticket id, and runs `tests/pipeline/run-all.sh` on every PR. Infra,
chore and dependency-bump PRs have no ticket, and the tooling self-test is irrelevant to nearly all PRs.

**Suggested fix.**

- Recognise an infra convention (see 4), for example a PR label `infra` that skips the ticket requirement
  but keeps everything else.
- Run the self-test only when files under `scripts/pipeline/`, `tests/pipeline/`, `.claude/` or
  `docs/pipeline/` change.

## 11. Plugin-owned agent files are edited in place

**What happened.** *Inferred.* The seven agents live in the project's `.claude/agents/` and are also
plugin-owned. In this install they were patched locally (the `origin/master` fixes), and `/pipeline-init`'s
promise is to "never overwrite your project-specific files". It is unclear whether a later update treats a
hand-edited agent file as project-specific or clobbers it.

**Suggested fix.**

- Record a hash or version per installed file so `/pipeline-init` can tell "untouched" (safe to update)
  from "customised" (merge or prompt).
- Better: keep project-specific behaviour out of agent bodies entirely (in `CONTEXT.md`, `pipeline.env`, or
  an optional `.claude/agents/<name>.local.md`), which removes the need to edit them at all. Items 2 and 3
  are the case in point.

---

## Suggested acceptance tests

Cheap tests that would have caught most of the above:

1. Install into a fixture whose trunk is `main` and whose remote is `origin` with unrelated history.
   Assert no literal `master` remains in installed agents, docs or workflows, and that the doctor flags
   the unrelated history.
2. With `TRACKER_TEAM_KEY=ABC`, assert that the guard hook, the PR gate workflow and `intake.sh` all
   accept `ABC-12` and reject `macos-14`, `UTF-8` and `v1.45.0-jammy`.
3. Run the guard hook on `git push --force-with-lease origin main` with no ticket, and assert the message
   names a route forward that does not involve the agent setting an override itself.
4. Install with `PIPELINE_HAS_DEPLOY_ENVS=no` and assert the resulting workflows do not fail on push.
5. Run the installer twice and assert `.gitignore` gains the pipeline entries exactly once, with no
   instruction text and no stray `.gitignore.pipeline`.
6. Against a tracker fixture with none of the labels or statuses, assert the doctor lists each missing
   item.
