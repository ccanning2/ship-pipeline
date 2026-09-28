# SHI-45 — Product definition

Status: approved
Type: feature
User-facing: yes
Priority: P2

## Problem & desired outcome
The last step of `/pipeline-init` is still the owner's. Init commits `chore: install ship pipeline`, and the guard
hook blocks the agent from pushing that commit to the trunk because the commit has no ticket. The agent then pushes a
branch and opens a pull request, and the owner has to open the host, mark the request `infra` (a label on GitHub and
GitLab, an `infra/…` branch on Bitbucket) and merge it. Until the owner does that, the pipeline is not on the trunk and
`/ship` cannot run.

The goal of init is that the owner answers once and does nothing afterwards except sign in. This ticket closes the
last gap. Init opens the install pull request and merges it itself. The guard hook allows that one kind of ticketless
merge by an agent, for init's install step only. Every other ticketless push or merge stays blocked, as it is today.

Outcome: on the default path (a supported host where nothing yet requires a review or the Pipeline Gate check on the
trunk), `/pipeline-init` ends with the install merged into the trunk. Nothing is left for the owner after the sign-in.

## Users affected
- **Installing developer** (runs `/pipeline-init`): has one less manual step, and the install is really finished
  when init reports it done.
- **Pipeline operator** (runs `/ship`): can start the first ticket right away.
- **Every consuming repo**: the guard hook is a write boundary (CONTEXT.md, high-risk). Its protection against
  ticketless agent merges must not get weaker in any case except the one described here.

## User stories
- US-1 (Must): As an installing developer, I want `/pipeline-init` to open the install pull request and merge it
  into the trunk itself, so that the install is finished without me doing anything on the code host.
- US-2 (Must): As a pipeline owner, I want the guard hook to allow that merge only when it can check that the merge
  really is init's install, so that no agent can pass other ticketless work through the same route.
- US-3 (Must): As an installing developer, I want init to stop cleanly and tell me the one thing to do when the host
  refuses the merge (a required review, a required check, a missing permission), so that I am never left with a
  half-finished install or a workaround I did not agree to.
- US-4 (Must): As an installing developer, I want to be able to say no to the automatic merge in the upfront
  questions, so that a team that wants a human review of the install keeps the current flow.
- US-5 (Should): As an installing developer re-running init to upgrade, I want the same automatic merge for the
  upgrade pull request when the host allows it, so that upgrades take no extra steps either.
- US-6 (Could): As an installing developer, I want the install branch deleted after the merge, so that no leftover
  branches build up.
- US-7 (Must, added in rework for SHI-55 / Q-1): As a pipeline owner, I want an unreviewed install to be unable to
  put anything in `pipeline.env` except the plain settings init itself writes, so that the automatic merge cannot
  land code that the guard, the pipeline scripts or CI would later run.

## Business rules & constraints
The owner asked for this change and explicitly approved changing the guard hook for it. The safety decisions are
recorded below. The BA and the engineer turn them into requirements and must not loosen them.

**R1. What counts as an init merge (how the guard tells it apart from any other ticketless merge).**
The guard decides by checking what is being merged, never by trusting what the command says about itself. A flag, an
environment variable, a marker file or a branch name that any agent can set must never be enough on its own.
Recommended default:
- a. There is one dedicated route for this merge, used only by `/pipeline-init`: a dedicated verb or script in
  `scripts/pipeline/`. The existing routes stay gated exactly as today: `git push` / `git merge` into the trunk,
  `gh pr merge`, `glab mr merge`, API merges and `host.sh merge`.
- b. The request comes from a reserved install branch name (the BA picks it). The branch name is only a label, not
  the proof.
- c. **The proof:** every file the request changes is one that `scripts/init.sh` installs or scaffolds. Each tooling
  file must be identical to the copy shipped by the plugin version doing the install. A request that changes any other
  file, or a tooling file that differs from the plugin's copy, is refused as ticketless work. For example, a
  hand-edited `guard-merge.sh`, `allow-paths.sh`, `gate.sh` or `.claude/settings.json` hook entry could otherwise
  weaken a safety boundary through this route. Refusing it closes that hole.
  - c-2. **`pipeline.env` (tightened in rework, owner decision Q-1 (a), 2026-09-28).** Other project-owned files
    in the install set stay free content. `scripts/pipeline/pipeline.env` does not. When the request adds or changes
    `pipeline.env`, the whole file, as it stands in the install commit, may hold only:
    1. comment lines and blank lines;
    2. assignments of the settings `init.sh` and `/pipeline-init` write, the keys of the shipped `pipeline.env`
       template, one per line, each at most once. The value is plain text: no variable, no command, no
       substitution, nothing run. The only thing allowed after it on the line is a trailing comment. The line has no
       `export` and no other statement;
    3. the one exception: the template's own `PIPELINE_TICKET_REGEX` line, exactly as the plugin ships it (it
       derives the pattern from `TRACKER_TEAM_KEY`). Writing that key as a plain value also passes.
    Anything else fails the proof, and the request is not treated as init's install. That includes an unknown key, a
    line that runs something, a value that refers to another variable or a command, a duplicate key, or a key that
    is no longer written (for example `PIPELINE_START_LEVEL`). The failure is reported the same way as any other
    file that is not part of the install, and names the file and the offending line. Init then falls back to the
    owner step as in R2: it opens the request and leaves it for the owner to review, mark `infra` and merge. Nothing
    is pushed to the trunk and nothing is overridden.
    The same rule applies in the guard's check and in the route's own check. A `pipeline.env` the request leaves
    unchanged is not examined by this rule, so an existing install's hand-edited file does not block an upgrade that
    does not touch it.
    This rule limits what an **unreviewed install** may carry. It does not change how the pipeline scripts, the guard
    or CI read `pipeline.env`, and it does not change which branches the guard trusts as trunk and staging. Those are
    follow-up SHI-56.
- d. The target is the trunk only. The route never moves the staging branch or a tag, never force-pushes and never
  deletes a protected ref.
- e. Refused and rejected alternatives: a session marker such as ".init is running" (any agent can write it); a
  per-command bypass flag (the same problem); a direct push of the install commit to the trunk without a pull
  request (keeping the pull request leaves a reviewable record on the host).

**R2. When the host blocks the merge (branch protection, a required review, a required check, rulesets).**
Recommended default: the agent never overrides the host. It never uses admin merge (`--admin`), never changes or
removes protection or rulesets, never adds or requests the `infra` label (still a human decision, and still blocked
by the guard), and never retries through another route. If the host refuses, init reports it in one line with the
link to the open pull request, and the fallback is today's flow: the owner marks it `infra` and merges it. The install
is otherwise complete, and the doctor result and the enforcement mode are reported as usual.

**R3. Order of steps on a first install.** Init's own branch protection requires the Pipeline Gate check, and a
ticketless install request would fail that check. So on a first install, init merges the install request **before**
it applies the branch protection the owner ticked. It then applies protection as today. The Pipeline Gate's
pass/fail conditions do **not** change in this ticket (CONTEXT.md requires the owner's say-so for that; see the
follow-up ticket). On a re-run where protection already requires the gate, the host refuses the merge and R2 applies,
so US-5 holds only where the host allows the merge.

**R4. Hosts.** Recommended default: every supported host, through `scripts/pipeline/host.sh`, the one host adapter:
GitHub (and GitHub Enterprise), GitLab (and self-managed) and Bitbucket Cloud. Bitbucket Data Center has no
Pipelines. Init still merges there when its API allows it, and otherwise falls back as in R2. The guard's recognition
(R1) is the same on every host.

**R5. Owner consent.** The merge is covered by the upfront consent question in `/pipeline-init` (Call 2, question 7),
checked by default. That question is limited to four options, so the BA fits it into the existing options rather
than adding a fifth. Recommended: extend "Branches" to cover "create, protect, and merge the install pull request".
When the owner leaves it unchecked, init behaves exactly as today.

**R6. Unchanged guarantees.** For every agent command outside R1 the guard behaves byte-for-byte as today. That covers
ticketless pushes and merges into the trunk or staging, force pushes, deletes, bulk pushes, version tags and the
`infra` label. `PIPELINE_BYPASS` keeps its current meaning. `/ship` never uses the init route.

**R7. Documentation and release.** `docs/pipeline/BRANCHING.md` ("Repository maintenance without a ticket"), the
guard's block message, `commands/pipeline-init.md` step 8, the README and the CHANGELOG say that init merges its own
install request and when it falls back to the owner. The personas stay project-agnostic. A new file in
`scripts/pipeline/` is a tooling path and must be classified in `init.sh`. This is a new capability, not a rename:
minor version bump.

**R8. Claims.** The docs must not say that the install is reviewed. They say that init merges it without a human
review, and that a team that wants a review leaves the merge unchecked (R5) or keeps a required review on the trunk
(R2).

## Success metrics
1. On a fresh install on each supported host with no existing trunk protection, the number of owner actions after
   the sign-in is 0, and the install commit is on the trunk when init reports done.
2. Zero regressions in the guard. Every existing `test_guard_merge.sh` case still blocks or allows as before. New
   cases show that a ticketless request with any file outside init's scaffold set, or with a tooling file that
   differs from the plugin's copy, or with a `pipeline.env` that breaks R1c-2, is blocked through the init route. A
   `pipeline.env` exactly as `init.sh` writes it still merges.
3. Whenever the host refuses the merge, init ends with one clear line and the pull request link. No protection,
   label or admin setting is changed.

## Out of scope
- Changing the Pipeline Gate (CI) pass/fail conditions so that a verified install request passes on an already
  protected trunk. This is follow-up SHI-46 and needs the owner's say-so under CONTEXT.md.
- Reading `pipeline.env` as data (never running it) in the pipeline scripts, the guard and CI, and deciding how far
  the guard trusts `BASE_BRANCH` / `STAGING_BRANCH` from the working tree. This is follow-up SHI-56, and it touches
  the write-boundary hooks and the gate (owner's say-so under CONTEXT.md). SHI-45 only limits what an unreviewed
  install may put in the file (R1c-2).
- Letting agents add the `infra` label, or use the init route for other ticketless maintenance (dependency bumps, CI
  migrations).
- Merging into the staging branch or tagging during init.
- `/pipeline-doctor` fixing things by merging.

## Open questions for the owner
- None blocking. Q-1 is answered: go-live waits for R1c-2. Widening the CI gate for upgrade re-runs on protected
  repos is follow-up SHI-46. The wider `pipeline.env` hardening is follow-up SHI-56.
