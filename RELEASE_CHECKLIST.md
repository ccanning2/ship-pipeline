# ship-pipeline — Pre-production release checklist

Owner: `app-specialist`, run against **staging** (= the `staging` branch ref; verified by installing
the plugin from that ref into a throwaway git repo and running the flow there — no host to hit).
Record PASS/FAIL/N/A with evidence in `signoff.md`. A FAIL in a section marked (blocking) blocks the release.

## 1. Build & tests (blocking)
- [ ] `bash tests/pipeline/run-all.sh` green; test count ≥ baseline and ≥ previous run.
- [ ] Every AC in requirements.md maps to a passing test (qa-report.md).
- [ ] Staging runs exactly the dev-checked, QA-tested sha (`releases.md` Dev = QA = Staging).
- [ ] Every AC walked end-to-end by installing the plugin from the staging ref into a throwaway repo.

## 2. Domain risks (blocking)
- [ ] Each high-risk area in CONTEXT.md (init.sh idempotency, gate.sh pass/fail conditions, the
      write-boundary hooks, promote.sh/next-version.sh, agent frontmatter, cross-platform shell)
      has been exercised on staging with evidence.

## 3. Security (blocking)
- [ ] No secrets in the diff, and `scripts/init.sh` writes only placeholder names of secrets/vars
      into a scaffolded repo — never real values.
- [ ] `scripts/pipeline/hooks/allow-paths.sh` and `guard-merge.sh` still enforce their write
      boundaries (tested, not just read).
- [ ] Ticket titles/descriptions/attachments (untrusted tracker input) are treated as data, not
      shell input, throughout `intake.sh` and the other scripts that consume them.

## 4. Data & migrations (blocking)
- [ ] N/A — no database. Confirm instead: `scripts/init.sh` never overwrites a project-owned file
      (CONTEXT.md, RELEASE_CHECKLIST.md, pipeline.env, `.github/workflows/*`, `scripts/deploy/*`,
      `.claude/settings.json`) on a re-run, and a half-applied install can't happen (arguments
      validated before anything is copied).
- [ ] Rollback approach documented (previous version tag; `git tag` history is the only rollback
      mechanism — there is nothing to migrate back).

## 5. Infrastructure & delivery
- [ ] N/A — no image, no host. Confirm instead: the plugin installs cleanly from the staging ref
      (`/plugin marketplace add`, `/plugin install`) into a clean checkout, and `/pipeline-init`
      scaffolds correctly into a throwaway target repo.
- [ ] `.claude-plugin/plugin.json` version matches the proposed `vX.Y.Z` tag.
- [ ] Previous production version tag recorded for rollback.

## 6. Product & brand
- [ ] product.md and requirements.md approved; research complete (features); no open clarifications.
- [ ] User-facing: marketing.md `ready` (only for changes visible to the installing developer, e.g.
      README/command UX — most engine-only changes are not user-facing; N/A otherwise), launch
      ticket done, copy defects verified.
- [ ] No product, person or vendor names introduced into `template/agents/*.md` or `commands/*.md`
      (the seven personas must stay project-agnostic — enforced by the test suite).

## 7. Tickets (blocking)
- [ ] Every `eng` ticket done. Every `defect` verified, or wontfix with product-owner agreement; no
      High-severity wontfix.
- [ ] `tickets.md` matches the tracker.

## 8. Docs
- [ ] `README.md`, `docs/pipeline/BRANCHING.md`, `docs/pipeline/TICKETS.md`, `docs/pipeline/CLOUD.md`
      updated for any tooling-path, agent-name or template-filename change (breaking change → bump
      minor version and say so in the release notes). Pipeline `STATUS.md` complete.
