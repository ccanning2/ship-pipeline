# Reputabill / Curate — Pre-prod release checklist

Owner: `app-specialist`, run against **staging**. For each item, record PASS, FAIL or N/A with evidence in `signoff.md`.
A FAIL in sections 2–6 or section 9 blocks the release.

## 1. Build & tests
- [ ] Backend: `./mvnw clean verify` is green, and the test count is ≥ the baseline in CONTEXT.md and ≥ the previous run.
- [ ] Frontend: `npm ci && npm test -- --watchAll=false && npm run build` is green, and lint is clean.
- [ ] Every AC in requirements.md maps to a passing test (see qa-report.md).
- [ ] Staging runs exactly the dev-checked, QA-tested sha (`releases.md` Dev = QA = Staging; health/version endpoint confirms it).
- [ ] Every AC was walked end-to-end on staging for each affected role.
- [ ] No skipped or `@Disabled` tests were added without a linked ticket.

## 2. Payments (Paystack / Peach)
- [ ] Sandbox charge success and failure paths are exercised.
- [ ] Webhook signature verification rejects tampered payloads.
- [ ] Webhooks are idempotent: a duplicate delivery has no double effect.
- [ ] Refund and cancellation paths are tested.
- [ ] No card or PAN data is stored or logged.

## 3. Escrow / booking state machine
- [ ] Only permitted transitions are possible, and illegal transitions are rejected and tested.
- [ ] The audit table stays append-only: no UPDATE/DELETE paths.
- [ ] Outbox rows are written in the same transaction and processed exactly once.
- [ ] The scheduler uses `FOR UPDATE SKIP LOCKED`, and a concurrent-release test proves there is no double payout.
- [ ] Release happens only after the event date plus the dispute window; an open dispute halts release.
- [ ] No user-facing claim of "escrow" unless the custody model is live and approved.

## 4. Proof documents & moderation
- [ ] Upload enforces a file type/size allowlist, and storage paths are not guessable.
- [ ] `portfolioConsent=false` documents never appear publicly.
- [ ] Flagged documents are hidden (`visible=false`) until moderated. Approve keeps them hidden; reject restores them.
- [ ] Proof documents appear only on the Portfolio tab, never on listings.
- [ ] A Verified badge requires qualifying proof; legacy reviews remain `UNVERIFIED`.
- [ ] POPIA: access control covers owner, moderator and admin roles only. No PII appears in logs.

## 5. Security (regression of audit findings + general)
- [ ] Invite acceptance is race-safe.
- [ ] Geocoding endpoint is rate-limited or authenticated.
- [ ] Async executors have bounded queues and backpressure.
- [ ] Trust-badge embed output is escaped (XSS test present).
- [ ] Avatars are not publicly enumerable.
- [ ] Backups are encrypted.
- [ ] Pagination `size` and `page` are validated and capped; admin list APIs are bounded.
- [ ] CSP is not loosened, or any change is justified in signoff.md.
- [ ] Authz: cross-vendor and cross-user access returns 403 or 404 (tested).
- [ ] No secrets in the diff.
- [ ] Dependency audit shows no new High/Critical findings (`./mvnw dependency-check:check` or equivalent, plus `npm audit --audit-level=high`).

## 6. Data & migrations
- [ ] Migrations are forward-only, apply cleanly on a prod-like snapshot, and contain no unapproved destructive DDL.
- [ ] The rollback approach is documented: a down script, or a mitigation if the migration is irreversible.
- [ ] Indexes exist for new query paths, and there are no N+1 queries on changed endpoints.
- [ ] A backup is taken before deploy.

## 7. Infrastructure & delivery (Hetzner)
- [ ] The image was built once (dev) and promoted unchanged, and the Trivy scan shows no unfixed High/Critical.
- [ ] CI/CD workflow changes were reviewed; secrets live only in GitHub environments.
- [ ] New env vars/config exist in the production environment before the deploy.
- [ ] JVM heap and container limits fit the CX32's memory alongside Postgres.
- [ ] HikariCP pool size is ≤ Postgres `max_connections` minus headroom.
- [ ] Health and readiness endpoints are green after deploy.
- [ ] The previous image/tag is recorded for rollback. No Friday deploy without monitoring.

## 8. Product & brand
- [ ] `product.md` and `requirements.md` are `approved`, with no open questions in `clarifications.md`; research is `complete` (for features).
- [ ] For user-facing changes, marketing.md is `ready` and all requested copy changes are applied.
- [ ] User-facing text says "Curate", with no stray "Reputabill" or "Viable Vendors".
- [ ] Empty, error and loading states exist for new UI.

## 9. Tickets
- [ ] Every `eng` ticket is done.
- [ ] Every `defect` ticket (dev/qa/staging) is verified, or wontfix with product-owner agreement; no High-severity wontfix.
- [ ] For user-facing work, the marketing launch ticket is complete.
- [ ] `tickets.md` matches the tracker.

## 10. Docs
- [ ] `BACKEND.md`, `FRONTEND.md` and `OVERVIEW.md` are updated.
- [ ] Pipeline `STATUS.md` is complete.
