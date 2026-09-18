# SHI-5 — Market research

Status: complete
Recommendation: build

Scope note: this is process/tooling work on the pipeline's own product. "Competitors" means other
release-orchestration tooling; "customer value" means value to the three user segments in
CONTEXT.md (plugin author / installing developer / pipeline operator), not end consumers.

## Product fit

Strong fit, and it is the pipeline's own stated unfinished business — CONTEXT.md lists both halves
of SHI-5 under **Open strategic questions** (`docs/pipeline/CONTEXT.md:82-83`), so this is closing a
known gap, not scope creep.

The product's positioning per CONTEXT.md is "a Claude Code plugin ... for developers and solo
founders running delivery on their own repos", installed into *other people's* repos via
`/pipeline-init`. A pipeline that only fits one project shape (a deployed web service with a
marketing function) contradicts that positioning. The plugin cannot credibly be a general-purpose
delivery pipeline while its single worked example — **this repo** — has to hand-edit its way around
the model.

That hand-editing is already visible in the repo and is the single most damning piece of evidence:

- `RELEASE_CHECKLIST.md:35-37` — section 5 "Infrastructure & delivery" is entirely `N/A — no image,
  no host`, replaced by prose telling the reader to install the plugin from a ref instead.
- `RELEASE_CHECKLIST.md:43-45` — the `User-facing` gate is narrowed by hand: *"only for changes
  visible to the installing developer ... most engine-only changes are not user-facing; N/A
  otherwise"*.
- `scripts/pipeline/pipeline.env:5,10` — `DEPLOY_WORKFLOW="deploy.yml"  # n/a here` and
  `HEALTH_PATH=""  # n/a`, with `DEV_URL`/`QA_URL`/`STAGING_URL` pointed at GitHub *tree refs*
  because there is no host.
- `docs/pipeline/CONTEXT.md:41-47` — an entire section redefining "environment" as "a ref people can
  install from, not a host", and instructing readers to ignore "build once, promote the image" in
  the generic docs.

Two of the three things a consumer owns (`CONTEXT.md`, `RELEASE_CHECKLIST.md`, `pipeline.env`) are
being used as a place to write *"ignore what the tooling says"*. That is a configuration problem
being solved with documentation, and it is the definition of a product-shape defect.

**Important correction to the ticket's framing.** The marketing persona is *already* conditional —
just at the wrong granularity:

- `commands/ship.md:46` — `## 7. Staging — app-specialist (+ marketing-specialist if User-facing: yes)`
- `scripts/pipeline/gate.sh:135` — `if [ "$uf" = yes ]; then require_file marketing.md; ...`

So the gap is not "marketing is unconditional". It is that the only available switch is the
**per-ticket** `User-facing: yes|no` flag set by the product owner (`agents/product-owner.md:21`),
and that flag is overloaded to carry two unrelated meanings: *does this change affect users?* and
*should a marketing persona run and produce launch content?* A solo founder shipping a library has
plenty of genuinely user-facing changes (README, command UX) and no marketing function at all. Today
their only escape is to mark user-facing work `User-facing: no` on every ticket — lying to the gate
to skip a persona — which also silently disables the marketing check for any project that later
*does* want it. Splitting project-level capability from per-ticket applicability is the actual fix.

## Customer value (plugin author / installing developer / pipeline operator)

| Segment | Pain removed | Strength |
|---|---|---|
| **Installing developer** | `/pipeline-init` currently scaffolds `scripts/deploy/{deploy,rollback,smoke}.sh` and `.github/workflows/deploy.yml` into every repo (`scripts/init.sh:49-50`), including libraries/CLIs/plugins that will never deploy. They are project-owned, so they are never cleaned up — permanent dead weight, plus a `deploy.yml` in `.github/workflows/` that a reader will reasonably assume is live. | High |
| **Pipeline operator** | Stops having to falsify `User-facing` to skip marketing, and stops hitting a production gate that demands a `marketing` ticket be `done` for a release with no audience to announce to (`gate.sh:135`). Removes a whole class of "the gate is wrong, override it" habits — which is corrosive, because the gate's credibility is the product. | High |
| **Plugin author (this repo)** | Can delete the `N/A` prose from `RELEASE_CHECKLIST.md` and the "ignore the generic docs" paragraph from `CONTEXT.md`, and dogfood the pipeline honestly rather than in a documented exception. | Medium-High |

Evidence quality: this is **primary** — it is the product's own repo, its own checklist, and its own
config file, all three carrying the workaround. There is no need to infer the pain from a listicle.
Sample size is the honest caveat: n=1 consuming project (`profiles/reputabill/` is the only other
profile, and it is a deployed service that wants marketing — `profiles/reputabill/RELEASE_CHECKLIST.md:67,74`).
No external user issues exist yet to corroborate demand from other installing developers — marked
UNVERIFIED. I do not think that weakens the case, because the library/CLI/plugin shape is not a
niche: it is the majority shape for the "developer tooling" repos this plugin is most likely to be
installed into first.

## Problem evidence

- Release Please treats project shape as a first-class config choice: a `release-type` /
  strategy parameter (node, python, maven, elixir, java, simple) selects the release behaviour from
  one tool, rather than forking the tool per shape — https://github.com/googleapis/release-please/blob/main/docs/customizing.md and https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md
- Backstage scaffolder templates support conditional steps and conditionally-shown fields driven by
  a parameter value, and golden-path guidance explicitly frames the path as "a starting point, not
  an endpoint" with optional steps for teams that need something outside the default —
  https://backstage.io/docs/features/software-templates/writing-templates/ and https://github.com/backstage/backstage/issues/5742
- GitHub Actions' native answer to "this stage does not apply here" is `if:` on the job, with the
  documented caveat that skipped jobs interact badly with required status checks in reusable
  workflows — i.e. the skip must be modelled deliberately, not improvised —
  https://docs.github.com/en/actions/using-jobs/using-conditions-to-control-job-execution and https://github.com/orgs/community/discussions/72708
- Multi-agent delivery pipelines for Claude Code exist as a category (e.g. Mozart, 14 specialist
  subagents through research -> plan -> review -> implement -> verify -> document) —
  https://github.com/jstuart0/mozart-orchestration — but I found no evidence of one shipping a
  *tracker-gated* release model with environment promotion; that remains this plugin's
  differentiator. UNVERIFIED that none exists; absence of search evidence only.
- Internal (primary, this repo @ 874db79): `RELEASE_CHECKLIST.md:35-45`, `scripts/pipeline/pipeline.env:5,10`,
  `docs/pipeline/CONTEXT.md:41-47,82-83`, `scripts/pipeline/gate.sh:135`, `commands/ship.md:46`,
  `scripts/init.sh:49-50`.

## Competitor coverage

| Competitor | Has it? | Notes |
|---|---|---|
| Release Please | Yes (shape), N/A (marketing) | `release-type` strategies make project shape a config value in one tool. Has no concept of environments at all — a library-shaped release tool by default. Direct precedent for "one tool, several shapes, selected by config". |
| Backstage golden paths | Yes | Conditional steps and conditional parameter visibility are documented features; golden-path guidance treats optional steps as the norm. The closest analogue to "optional persona". |
| GitHub Actions release templates | Yes, crudely | `if:` per job is the universal escape hatch; every serious template repo uses it. Table stakes — the bar is "can I turn a stage off without editing the tool". |
| semantic-release / Changesets | N/A (by omission) | These *are* the library shape: version + tag + changelog, no environments. Their existence is the market's answer that a deployless release path is a legitimate first-class mode, not a degraded one. UNVERIFIED (not searched directly this round). |
| Claude Code pipeline plugins/skills | Partially | Orchestration plugins exist (Mozart et al.). None found combining tracker-gated handoffs with env promotion; per-project stage toggling is not a visible differentiator in that space yet. |

**Verdict: table stakes, not a differentiator.** Every mature tool in this category lets you turn a
stage off by configuration. The pipeline currently does not (at project level), and that is a gap
against the field rather than an opportunity to lead. It should be built because its absence is
conspicuous, not because it will win anyone over.

## Fit with positioning

Table stakes — and the pipeline's *positioning* depends on it. CONTEXT.md commits to keeping the
seven personas project-agnostic with everything project-specific in `CONTEXT.md` /
`RELEASE_CHECKLIST.md` / `profiles/` (`CONTEXT.md:51-58`). Today the tooling violates its own rule:
a host-deploy-and-marketing assumption is baked into `gate.sh`, `promote.sh`, `ship.md` and the
files `init.sh` scaffolds, and consumers are told in prose to ignore it. Making shape and marketing
into configuration moves the project-specific decision back where the architecture says it belongs.

Two opinions I want carried into the product stage:

1. **Do not fork the pipeline into two shapes.** One pipeline with capability flags, defaulting to
   today's behaviour. A second "library pipeline" would double the surface of `gate.sh` — the file
   CONTEXT.md names as a high-risk area where "a gate that wrongly passes lets unreviewed work reach
   production in every consuming repo" (`CONTEXT.md:68-70`). Release Please's strategy pattern is
   the model to copy: one engine, a shape parameter.
2. **Keep the stages; change what satisfies them.** A library still wants a dev self-check, a QA
   pass and a pre-production sign-off — this repo already does all three, against installable refs
   rather than hosts (`CONTEXT.md:41-47`). What should become optional is the *deploy/smoke/health*
   machinery and the *marketing* persona, not the review gates. Deleting stages for libraries would
   hollow out the product's core claim.

## Regulatory & risk flags

- **Data protection / POPIA / GDPR: N/A.** CONTEXT.md:22-23 — the plugin handles no personal data.
- **Payments/custody: N/A.** No payments surface in this product.
- **Secrets (the one real rule):** CONTEXT.md:23 — the plugin must never write secrets into a
  scaffolded repo, only placeholder names. Any new config keys must be placeholder-only; a
  "no-deploy" mode should if anything *reduce* secret surface by not scaffolding deploy workflows.
- **Breaking-change risk (the real exposure, not regulatory):** `scripts/pipeline/pipeline.env` is
  project-owned and is never overwritten by `init.sh` (`init.sh:25-28,48`). Existing installs will
  therefore **never receive new config keys**. Any flag introduced here must default, in the
  scripts, to today's behaviour (e.g. `${VAR:-<current>}`) or every live consumer's gate breaks on
  the next `/pipeline-init`. CONTEXT.md:59-64 also requires a stop-and-ask before changing the
  gate's pass/fail conditions, and a minor version bump plus release-note callout for any
  tooling-path, agent-name or template-filename change. This work touches all of that.
- **Incidental defect found while writing this file (not part of SHI-5's scope, but the product
  owner should see it):** `scripts/pipeline/hooks/allow-paths.sh:17` normalises the write path with
  `case "$path" in "$project"/*)`, which cannot match a Windows backslash path, so the relative path
  is never derived and every allow-glob misses — a legitimate, explicitly-permitted write is
  blocked. This hook is named in CONTEXT.md:71-72 as a write-boundary high-risk area, and
  CONTEXT.md:75 already flags cross-platform shell as high-risk. Worth its own ticket.

## Summary

Build — and build both halves together, because they are the same defect: project shape is hardcoded
into tooling that ships into other people's repos. The strongest evidence is internal and primary:
this repo's own `RELEASE_CHECKLIST.md`, `CONTEXT.md` and `pipeline.env` all carry hand-written
"N/A — ignore the tooling" workarounds for exactly these two gaps. Competitively this is table
stakes (Release Please's `release-type`, Backstage's conditional steps, `if:` in Actions), so it
wins nothing, but its absence is conspicuous for a plugin that markets itself as installable into
any repo. The biggest risk is not product risk but blast radius: `gate.sh` is the safety boundary
for every consuming repo, `pipeline.env` never updates in place, and the correct answer to the
ticket's framing is per-project capability flags that default to current behaviour — not a second
pipeline shape, and not deleting review stages for libraries.
