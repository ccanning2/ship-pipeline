# Reputabill / Curate — Shared agent context

All pipeline agents read this file. Keep it current; the PM owns it.

## Product
- Brand: **Curate** (formerly Reputabill / Viable Vendors). Tagline "Rated by Reality". Palette: amber and ink.
- A verified business review and vendor marketplace for South Africa. Reviews are backed by real proof: receipts, photos, invoices, contracts.
- Beachhead: weddings, positioned as a verified trust layer, with expansion to adjacent events later.
- Differentiator: proof-backed reviews. SA incumbents are listing-only directories.

## Stack
- Backend: Spring Boot 3.3, Java 21, PostgreSQL.
- Frontend: React.
- Payments: Paystack and Peach Payments.
- Hosting: Hetzner CX32.
- Backend test suite baseline: ~1,861 passing tests (update when it grows). The count must never drop.

## Environments & delivery
- dev ← merge to `master` · qa ← push to `staging` branch · staging ← dispatch of the same sha · production ← tag `vX.Y.Z` (see BRANCHING.md). Hetzner, GitHub Actions (`deploy.yml`). URLs in `scripts/pipeline/pipeline.env`.
- **Build once:** the image `ghcr.io/<repo>:<sha>` is built on the way into dev, promoted unchanged, and tagged `:vX.Y.Z` in production.
- **Tracker:** Linear (team REP) is the source of truth and the handoff medium between personas; see `docs/pipeline/TICKETS.md`.
- **Production** requires the app-specialist's staging sign-off plus Chris's explicit go-live.
- **The senior engineer owns** all of development, CI/CD and DevOps.

## Built / designed capabilities
- Proof-document pipeline:
  - `ProofDocument` has `portfolioConsent` (set by the user at upload) and `visible` (false when a business flags the document).
  - `DocumentModerationRequest` feeds an admin/moderator queue. Approve keeps the document hidden; reject restores visibility.
  - A Portfolio tab on the business page groups documents by service type. Proof documents do not appear on listings outside that tab.
  - Business owners see all proof documents linked to them.
  - Storage is local for now; S3-compatible storage is planned.
- Tiered verification: legacy and text-only reviews are `UNVERIFIED`; the Verified badge is earned with proof.
- Escrow / delayed-payout design (ESCROW_FEATURE_SPEC.md, BACKEND.md):
  - plain Spring state machine, append-only audit table, transactional outbox, `FOR UPDATE SKIP LOCKED` scheduler;
  - release is triggered by the event date plus a dispute window;
  - **no Axon / event sourcing** (explicitly rejected).
- Security audit remediation covered 9 findings:
  - invite-acceptance race;
  - geocoding abuse;
  - unbounded async backpressure;
  - trust-badge embed XSS;
  - avatar enumeration;
  - unencrypted backups;
  - pagination validation;
  - unbounded admin lists;
  - permissive CSP.

## Open strategic questions (do not assume resolved)
- Custody model for held funds. PSP split payments route money at settlement and don't hold it conditionally. The options are:
  - a licensed partner's rails (attorney trust account or BaaS);
  - TPPP registration via a sponsor bank under PASA;
  - waiting for the SARB activity-based framework.
- Konnetta also holds payments, so an escrow-marketplace position overlaps.
- Pivot concepts reusing the proof and ledger infrastructure are under consideration:
  - rental deposit protection;
  - verification-as-a-service;
  - a stokvel ledger;
  - a wedding planning OS;
  - contractor project protection.
- One brand spanning weddings → events, or a wedding-first sub-brand?
- Vendor pricing model (listing vs lead vs subscription).
- Seating/floor-plan planner: an engagement lever, not a trust lever.

## Competitors to track
Pink Book, The Wedding Inventory, Weddings.africa, Wedding & Function, The Wedding Catalogue, Konnetta, Linnets, Bark, and HelloPeter (as a complaints signal).

## Compliance
- POPIA: proof documents contain personal information. Apply access control, minimisation and retention.
- Payments: keep card data with the PSP. Verify webhook signatures and make handlers idempotent.

## Stack & commands
- Backend tests: `./mvnw -B clean verify` (baseline ~1,861). Frontend: `npm ci && npm test -- --watchAll=false && npm run build`.
- Architecture docs: `OVERVIEW.md`, `BACKEND.md`, `FRONTEND.md`.

## Marketing channels
- Instagram, Facebook, LinkedIn, X/Threads, WhatsApp broadcast, in-app announcement. Audiences: vendors; couples/customers.
