# SHI-5 — Clarifications

<!-- One block per question. To: PO | Owner. State: open | answered -->

### Q-1
To: Owner
State: open
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
Answer:

### Q-2
To: Owner
State: open
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
Answer:
