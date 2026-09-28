# SHI-45 — Clarifications

<!-- One block per question. To: PO | Owner. State: open | answered -->

## Q-1 (To: Owner, Status: answered, State: answered). Does the v3.2.0 go-live wait for follow-up SHI-56 (pipeline.env)?
Asked: 2026-09-28 by business-analyst. Blocks: go-live only (not the SHI-55 build).
Context:
- `scripts/pipeline/pipeline.env` is class F (any content) in the install proof.
- It is `source`d by most pipeline scripts, by the guard hook for every command (through `base-ref.sh`), and by
  `gate.sh`, which the Pipeline Gate runs in CI.
- Before v3.2.0 a human merged every install. From v3.2.0 on, the install route can land an agent-written
  `pipeline.env` on the trunk with no ticket and no review.
- That content can run code in CI, change which branch the guard treats as the trunk or staging, or send a Bitbucket
  token to another host through `GIT_HOST_URL`.
- SHI-55 stops the route itself from being steered by pipeline.env (FR-18). It does not stop the merged file being
  used later.

Options:
- (a) Go-live waits for a narrow fix. A new eng ticket under SHI-45 limits `pipeline.env` in the install diff to
  comments, blank lines and literal assignments of the keys `init.sh` and `/pipeline-init` write. This is stricter
  than R1c today, so it needs a short PO confirmation. SHI-56 keeps the wider hardening.
- (b) Go-live after SHI-55 only. SHI-56 follows in a later release, and the CHANGELOG states the limit.

Recommendation: (a). It closes the gap v3.2.0 opens and costs nothing on the default path.
Answer: (a), owner, 2026-09-28. Go-live waits for the narrow fix: a new eng ticket under SHI-45 limits pipeline.env in the install diff to comments, blank lines and literal assignments of the keys init.sh and /pipeline-init write, built with SHI-55 in this rework loop. PO to confirm the R1c tightening; SHI-56 keeps the wider hardening.
PO confirmation (product-owner, 2026-09-28): confirmed and written into product.md as R1c-2 (plus US-7 and success metric 2). When the install diff adds or changes `pipeline.env`, the whole file at the install commit may hold only:
- comments and blank lines;
- one plain-value assignment per line of a key in the shipped `pipeline.env` template, each key at most once, with an optional trailing comment and no `export`, variable, command or substitution;
- the template's own `PIPELINE_TICKET_REGEX` line, exactly as shipped.
Anything else fails the proof (reported like `NOT-INSTALL`, naming the file and the line), and init falls back to the owner step. The same rule applies in the guard and the route. An unchanged `pipeline.env` is not examined. Reading `pipeline.env` as data everywhere, and how far the guard trusts BASE_BRANCH / STAGING_BRANCH, stay in SHI-56. No other R-rule changes.
