# SHI-5 — Clarifications

<!-- One block per question. To: PO | Owner. State: open | answered -->

### Q-1
To: Owner
State: answered
Asked by: product-owner
Needed by: stage 5 (build) — does not block analysis
Question:
SHI-5 is classified `User-facing: yes`, so under today's rules its own production gate requires a
completed `marketing` ticket. Part of this work (BR-15) switches THIS repo onto the new settings,
including turning its marketing capability off — which takes effect the moment it is committed, i.e.
for SHI-5's own remaining stages. Do you want SHI-5 to finish under the old rules (run the marketing
stage for this release, flip the setting afterwards), or under the new ones (flip during the build,
SHI-5 skips marketing and is the first release to prove the new behaviour)?
Recommendation: flip during the build. This repo has no marketing function, and dogfooding it is the
point of the ticket.
Answer: New rules — flip this repo's marketing capability off during the build. SHI-5 skips its own
marketing stage. (2026-09-18)

### Q-2
To: Owner
State: answered
Asked by: product-owner
Needed by: stage 5 (build) — does not block analysis
Question:
This work changes `gate.sh`'s pass/fail conditions: the production gate's marketing requirement
becomes conditional on the project-level marketing capability, and deploy-related checks become
conditional on the project having deployable environments. `docs/pipeline/CONTEXT.md` requires a
stop-and-ask before the gate's pass/fail conditions change. Do you approve that change in principle,
and do you want to review the exact before/after conditions before the engineer starts?
Recommendation: hold the approval until the business analyst has written the exact conditions into
requirements.md, then approve that specific list — not a blanket permission to edit the gate.
Answer: Not approved yet — wait for the business analyst to write the exact before/after gate.sh
conditions into requirements.md, then bring that specific list back for approval. (2026-09-18)
Follow-up (business-analyst, 2026-09-18): the exact list is now written as `requirements.md` §4
("`gate.sh` pass/fail conditions — exact before/after"), including the verbatim current line
(`scripts/pipeline/gate.sh:135`), the one-conjunct change, a full truth table showing that exactly
one cell moves, and an enumerated list of every condition that does NOT change. The approval itself
is raised as Q-3.

### Q-3
To: Owner
State: open
Asked by: business-analyst
Needed by: stage 5 (build) — blocks ONE eng ticket (the `gate.sh` change), not the whole stage
Blocks: the eng ticket "Production gate: marketing requirement becomes conditional". Every other eng
ticket is unblocked and may proceed in parallel.
Question:
This is the BR-9 stop-and-ask you deferred in Q-2. Please approve `requirements.md` §4 as a specific
diff. In one sentence, what changes in `scripts/pipeline/gate.sh`:

  BEFORE (line 135, production stage):
    if [ "$uf" = yes ]; then require_file marketing.md; expect marketing.md Status ready; \
      [ -n "$(rows_where '$2=="marketing" && $5=="done"')" ] || fail "no completed marketing launch ticket"; fi

  AFTER:
    if [ "$uf" = yes ] && [ "$has_marketing" = yes ]; then <the same three checks, unchanged> fi

  where `has_marketing` is `no` only when `scripts/pipeline/pipeline.env` sets
  `PIPELINE_HAS_MARKETING` to exactly `no` (trimmed, lowercased); absent, empty or any unrecognised
  value resolves to `yes` = today's behaviour.

Nothing else in `gate.sh` changes: not the build/dev/qa/staging stages, not the sign-off, defect,
High-severity-wontfix, Go-live, Version or tag checks, and not the `User-facing: yes|no` validation.
`PIPELINE_HAS_DEPLOY_ENVS` changes **no** `gate.sh` condition at all — the gate has no deploy, smoke
or health check to make conditional; that work is confined to `promote.sh` and `init.sh`.
Net effect: exactly one cell of the truth table moves — *project marketing off + ticket user-facing*
goes from "marketing.md `ready` and a done `marketing` ticket required" to "not required". Every
existing install (no key in `pipeline.env`) is unaffected, which is proven by a release-blocking test
(requirements.md AC-12).
Recommendation: approve as written. The change can only ever relax the gate through a `no` that the
project's own owner committed to a project-owned file; every other input, including a typo, keeps
today's stricter behaviour.
