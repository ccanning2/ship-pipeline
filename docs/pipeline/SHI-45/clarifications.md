# SHI-45 — Clarifications

<!-- One block per question. To: PO | Owner. State: open | answered -->

## Q-1 (To: Owner, Status: needs-input, State: open). Does the v3.2.0 go-live wait for follow-up NEW-1 (pipeline.env)?
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
  than R1c today, so it needs a short PO confirmation. NEW-1 keeps the wider hardening.
- (b) Go-live after SHI-55 only. NEW-1 follows in a later release, and the CHANGELOG states the limit.

Recommendation: (a). It closes the gap v3.2.0 opens and costs nothing on the default path.
Answer:
