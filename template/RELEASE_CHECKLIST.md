# __PROJECT_NAME__ — Pre-production release checklist

Owner: `app-specialist`, run against **staging**. Record PASS/FAIL/N/A with evidence in `signoff.md`.
A FAIL in a section marked (blocking) blocks the release.

## 1. Build & tests (blocking)
- [ ] Full backend and frontend suites green with the commands in CONTEXT.md; test count ≥ baseline and ≥ previous run.
- [ ] Every AC in requirements.md maps to a passing test (qa-report.md).
- [ ] Staging runs exactly the dev-checked, QA-tested sha (`releases.md` Dev = QA = Staging).
- [ ] Every AC walked end-to-end on staging for each affected role.

## 2. Domain risks (blocking)
- [ ] Each high-risk area in CONTEXT.md has been exercised on staging with evidence.

## 3. Security (blocking)
- [ ] Authz: cross-user/tenant access returns 403/404 (tested). Input validation on new endpoints; pagination capped.
- [ ] No secrets in the diff. Dependency audit shows no new High/Critical.
- [ ] No sensitive data in logs.

## 4. Data & migrations (blocking)
- [ ] Migrations forward-only, applied cleanly to staging data, no unapproved destructive DDL.
- [ ] Rollback approach documented (previous version tag + migration reversibility or mitigation).
- [ ] Indexes for new query paths; no N+1 on changed endpoints. Backup taken before production deploy.

## 5. Infrastructure & delivery
- [ ] Image built once (dev) and promoted unchanged; scan shows no unfixed High/Critical.
- [ ] New env vars/config exist in production before deploy. Health endpoint green after deploy.
- [ ] Previous production version tag recorded for rollback.
- [ ] With `PIPELINE_HAS_DEPLOY_ENVS="no"` there is nothing to deploy: confirm instead that the same
      sha reached `master`, the `staging` branch and the version tag, and that the artefact installs
      from the staging ref.

## 6. Product & brand
- [ ] product.md and requirements.md approved; research complete (features); no open clarifications.
- [ ] `User-facing: yes` **and** `PIPELINE_HAS_MARKETING="yes"`: marketing.md `ready`, launch ticket
      done, copy defects verified. With either one off, marketing is skipped by configuration — say so
      in `signoff.md` rather than leaving it blank.
- [ ] Empty, error and loading states exist for new UI.

## 7. Tickets (blocking)
- [ ] Every `eng` ticket done. Every `defect` verified, or wontfix with product-owner agreement; no High-severity wontfix.
- [ ] `tickets.md` matches the tracker.

## 8. Docs
- [ ] Architecture docs named in CONTEXT.md updated. Pipeline `STATUS.md` complete.
