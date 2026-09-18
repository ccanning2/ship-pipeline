# SHI-5 — Product definition

Status: approved
Type: feature
User-facing: yes
Priority: P2

## Problem & desired outcome

The pipeline assumes one project shape: a service that deploys to hosted environments and has a
marketing function. Every project that installs it inherits that assumption, whether or not it fits.

Two consequences, both visible in this repo today:

1. **Marketing is only switchable per ticket.** The single available switch is `User-facing: yes|no`
   on each ticket, which the product owner sets. That one flag is carrying two unrelated meanings —
   *does this change affect users?* and *should a marketing persona run and produce launch content?*
   A project with no marketing function has only one escape: mark genuinely user-facing work
   `User-facing: no`, ticket after ticket. That is lying to the gate to skip a persona, and it
   silently disables the marketing check for the day the project does want it.
2. **Deploy/environment machinery is unconditional.** `/pipeline-init` scaffolds
   `scripts/deploy/{deploy,rollback,smoke}.sh` and `.github/workflows/deploy.yml` into every repo,
   including libraries, CLIs and plugins that will never deploy. Those files are project-owned, so
   they are never cleaned up: permanent dead weight, plus a `deploy.yml` sitting in
   `.github/workflows/` that any reader will reasonably assume is live.

This repo is the proof. It works around both gaps in prose, inside the three files a consumer owns:
`RELEASE_CHECKLIST.md` section 5 is "N/A — no image, no host"; its `User-facing` line is hand-narrowed
to "only for changes visible to the installing developer"; `pipeline.env` carries
`DEPLOY_WORKFLOW="deploy.yml"  # n/a here` and `HEALTH_PATH=""  # n/a` with the environment URLs
pointed at GitHub tree refs; `CONTEXT.md` has a whole section telling readers to ignore what the
generic docs say about promoting an image. A configuration problem is being solved with
documentation, in the files that are meant to describe the project — not to apologise for the tool.

**Desired outcome.** Project shape becomes configuration, declared once per project and read by the
tooling. One pipeline, two independent capability switches, both defaulting to exactly today's
behaviour. After this change: a library-shaped project installs the pipeline and runs all ten stages
without a single hand-written exception; a project with no marketing function never sees the
marketing persona; and `User-facing` goes back to meaning only what it says.

## Users affected

- **Installing developer** (runs `/pipeline-init`) — primary. Stops receiving deploy scripts and a
  deploy workflow for a project that has nothing to deploy. Declares the project's shape once.
- **Pipeline operator** (runs `/ship` day to day) — primary. Stops falsifying `User-facing` to skip a
  persona, and stops hitting a production gate that demands a completed marketing ticket for a
  release with no audience to announce it to. This matters beyond convenience: the gate's
  credibility is the product, and every "the gate is wrong, override it" habit corrodes it.
- **Plugin author (this repo)** — secondary. Can delete the exception prose from
  `RELEASE_CHECKLIST.md`, `CONTEXT.md` and `pipeline.env` and dogfood the pipeline honestly.
- **Product owner and marketing-specialist personas** — the `User-facing` flag gets its single
  meaning back; the marketing persona is invoked on projects that actually have that function.

## User stories

- **US-1 (Must)** — As an installing developer whose repo is a library, plugin or CLI, I want to
  declare that the project has no deployable environments, so that the pipeline never scaffolds,
  runs or gates on deploy, smoke and health-check machinery I will never use.
- **US-2 (Must)** — As a pipeline operator on a project with no marketing function, I want marketing
  turned off once at project level, so that the marketing persona is never invoked and the production
  gate never asks for launch content, on any ticket.
- **US-3 (Must)** — As a product owner persona, I want `User-facing: yes|no` to mean only "does this
  change affect users", so that I can classify a ticket honestly without that classification
  deciding whether a persona runs. Marketing applicability becomes: *project has marketing* **and**
  *this ticket is user-facing*.
- **US-4 (Must)** — As a pipeline operator on a live install whose `pipeline.env` predates this
  release, I want the pipeline to behave exactly as it does today when the new settings are absent,
  so that updating the plugin or re-running `/pipeline-init` cannot break my gates.
- **US-5 (Must)** — As the owner, I want dev self-check, QA, staging sign-off and go-live to stay
  mandatory in every project shape, so that opting out of deployments never removes a human review.
- **US-6 (Should)** — As an installing developer, I want `/pipeline-init` to set the project's
  capabilities at install time and to scaffold only the files that shape needs, so that a fresh
  install is correct without me deleting files afterwards.
- **US-7 (Should)** — As the plugin author, I want this repo switched onto the new settings and its
  workaround prose deleted, so that the product's own worked example is honest.
- **US-8 (Should)** — As an installing developer on an existing install, I want the release notes and
  docs to tell me the new settings exist, what the defaults are and how to opt out, so that I can
  adopt this deliberately rather than discover it.
- **US-9 (Could)** — As a pipeline operator, I want `/ship` and `status.sh` to show which stages are
  disabled for this project, so that "marketing did not run" is visibly a setting and not a bug.

## Business rules & constraints

**Capability model**

- **BR-1** Two *independent* project-level capabilities, not one "project shape" enum:
  *has deployable environments* (yes/no) and *has a marketing function* (yes/no). They are
  genuinely independent — a deployed internal service may have no marketing function, and an
  open-source library with no environments may very much want launch content. Anything that forces
  them to move together is wrong.
- **BR-2** The capabilities are **machine-readable project configuration** (i.e. `pipeline.env`,
  which `gate.sh`, `promote.sh` and `init.sh` already source), not prose in `CONTEXT.md`. The
  tooling must be able to read them; `CONTEXT.md` explains them in words for the personas.
- **BR-3** Capabilities are **project-level and set once**. They must not become a per-ticket
  override, and no persona may change them mid-pipeline. Only the project's owner edits them, in a
  project-owned file.
- **BR-4** `User-facing: yes|no` on the ticket keeps its original single meaning and stays the
  product owner's call. It no longer decides, by itself, whether marketing runs.

**Backwards compatibility — the highest risk in this ticket**

- **BR-5** `scripts/pipeline/pipeline.env` is project-owned and is **never overwritten** by
  `scripts/init.sh` on a re-run. Every existing install therefore will **never receive a new key**.
  Any new setting must therefore default, inside the scripts themselves, to **today's behaviour**
  (`${VAR:-<today's value>}`): deployments on, marketing driven by the per-ticket `User-facing`
  flag. A missing key must be indistinguishable from today. This is a release-blocking rule, and it
  must be proven by a test that runs the gates against a `pipeline.env` with none of the new keys.
- **BR-6** No stage is deleted and no second pipeline shape is created. One `gate.sh` with
  conditional requirements, not a forked "library" code path — `gate.sh` is named in CONTEXT.md as a
  high-risk area where "a gate that wrongly passes lets unreviewed work reach production in every
  consuming repo", and doubling its surface is the opposite of what this ticket is for.
- **BR-7** The review gates are **not** optional in any shape: dev self-check, QA pass, staging
  sign-off, defect closure rules and the owner's go-live decision apply to every project. Only the
  *deploy / smoke / health-check* machinery and the *marketing persona* become optional. A library
  still has environments in the sense that matters — refs people can install from — and still gets
  master → staging branch → version tag.
- **BR-8** A capability may only ever **relax** a requirement when the project has explicitly
  declared the opt-out. A missing, empty or unrecognised value must fall back to the strict
  (today's) behaviour, never to the permissive one. Fail closed.

**Approval and release constraints (CONTEXT.md engineering rules)**

- **BR-9** This work **does** change `gate.sh`'s pass/fail conditions (the production gate's
  marketing requirement becomes conditional on the project capability, and deploy-related checks
  become conditional). CONTEXT.md requires a stop-and-ask with the owner before that. The engineer
  must obtain the owner's explicit approval of the **specific** conditions being changed — in
  writing on the ticket — before implementing the gate change. See Q-2.
- **BR-10** This work changes what `/pipeline-init` scaffolds and how the gates behave for every
  installed project. That is a breaking-ish change for installing developers: **bump the minor
  version** and call it out in the release notes, per CONTEXT.md. If implementation renames or
  removes a script in `scripts/pipeline/`, that is a separate stop-and-ask.
- **BR-11** The seven personas stay project-agnostic. No product, person or vendor names may enter
  `template/agents/*.md` or `commands/*.md` (enforced by the test suite). The marketing persona is
  *skipped by configuration*, not edited to know about project types.
- **BR-12** No secrets. New configuration keys are placeholder names and booleans only. A project
  that opts out of deployments should end up with *less* secret surface, not more — no deploy
  workflow, no environment secrets.
- **BR-13** `scripts/init.sh` stays idempotent and must never overwrite a project-owned file. For an
  existing install that already has `scripts/deploy/*` and `.github/workflows/deploy.yml`, opting
  out of deployments must **not** delete them — the pipeline stops using them; the owner decides
  whether to remove them.
- **BR-14** Cross-platform: the new logic must work on Windows/Git-Bash and macOS BSD tooling, which
  CONTEXT.md lists as a high-risk area (and which has already bitten this ticket once, in
  `hooks/allow-paths.sh`).

**Dogfooding**

- **BR-15** This repo must be switched onto the new settings as part of this work, and the
  workaround prose removed from `RELEASE_CHECKLIST.md` (sections 5 and 6), `CONTEXT.md`
  (the "Environments" caveats and the SHI-5 open question) and `pipeline.env` (the `# n/a` comments).
  Those three files are project-owned: the *change* is made here by hand, and must not be pushed
  into other consumers' copies by `init.sh`.
- **BR-16** Timing caveat: flipping this repo's own settings takes effect the moment it is
  committed, including for SHI-5's own remaining stages. SHI-5 is classified `User-facing: yes`, so
  under today's rules its own production gate requires a completed marketing ticket. Whether SHI-5
  runs under the old rules or the new ones is the owner's call — see Q-1.

## Success metrics

1. **Zero hand-written exceptions.** The four "N/A / ignore the tooling" workarounds in this repo
   (`RELEASE_CHECKLIST.md` §5 and §6, `CONTEXT.md` Environments, `pipeline.env` `# n/a` comments)
   go from 4 to 0, with nothing equivalent introduced elsewhere.
2. **A library-shaped install needs no overrides.** A fresh `/pipeline-init` into a repo declared as
   having no environments and no marketing scaffolds no `scripts/deploy/*` and no
   `.github/workflows/deploy.yml`, and a ticket runs all ten stages to a version tag with zero gate
   overrides and zero falsified `User-facing` values.
3. **No existing install regresses.** A `pipeline.env` containing none of the new keys produces
   byte-identical gate outcomes before and after this release, proven by the test suite.

## Out of scope

- Making `scripts/deploy/*` pluggable per target (Hetzner/docker-compose specific today) — related
  CONTEXT.md open question, separate ticket. → follow-up.
- A versioned migration step that pushes new `pipeline.env` keys into existing installs. BR-5 makes
  it unnecessary for this release; it stays an open CONTEXT.md question. → follow-up.
- Distributing profiles separately from the plugin.
- New profiles (e.g. a ready-made "library" profile pair). The capability flags come first; a
  profile is just a preset of them and can follow.
- Changing the branch/tag model, the ten stages, the persona roster or any review gate.
- Making any other persona optional (market-researcher, QA, app-specialist). Only marketing is in
  scope; the ticket says marketing, and the review personas are the product's core claim.
- Fixing `docs/pipeline/_templates/research.md`, which still carries placeholder text from an
  unrelated product and ships to every consumer. → follow-up.

## Open questions for the owner

Neither question blocks the analysis stage. Both must be answered before the engineer implements
(stage 5, build). Logged in `clarifications.md`.

- **Q-1 — Does SHI-5 itself run under the old rules or the new ones?** SHI-5 is `User-facing: yes`,
  so as things stand its own production gate will require a `marketing` ticket to be done. If we
  flip this repo's marketing capability off during the build (BR-15), SHI-5 skips its own marketing
  stage. *My recommendation:* flip it — that is the dogfooding proof, and this repo genuinely has no
  marketing function. But it is your call, because it changes this release's own gate mid-flight.
- **Q-2 — Approval to change `gate.sh`'s pass/fail conditions (BR-9).** CONTEXT.md requires a
  stop-and-ask. The precise conditions are not yet written — the business analyst will specify them.
  *My recommendation:* answer this when the BA presents the exact before/after conditions, so you are
  approving a specific diff rather than a blank cheque.
