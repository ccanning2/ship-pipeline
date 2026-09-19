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
State: answered
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
Answer: Approved as written. (2026-09-18)

### Q-4
To: Owner
State: answered
Asked by: orchestrator
Needed by: go-live (and the plugin.json / README / AC-35 content, which QA tests)
Question:
`next-version.sh` proposes v0.1.0 because the repo has no tags, while SHI-19 set plugin.json to 1.1.0
and the README notes to v1.1.0 (AC-35 asserts both). Which version is this release tagged as?
Options put to the owner: v1.1.0 (matches everything already written) or v0.1.0 (would read as a
downgrade from the released 1.0.0). The owner first said 0.1.0, then, when told what it collides with,
answered "1.0.0" and, asked whether that meant tagging the old baseline or this build, chose this build.
Answer: Release THIS build as v1.0.0. (2026-09-19)
Consequences. Put to the owner before they chose: (1) plugin.json, the README release notes and the
AC-35 test change with it; (2) 1.0.0 is already released (167445e) and a 1.0.0 copy is installed, so two
different builds carry the same version number. The owner was told this would cost a second rework loop;
the orchestrator later found it can ride the still-open loop 1/3 instead, because the fixes have not been
promoted to dev yet, so QA tests the final content once. Added by the orchestrator, NOT put to the owner
beforehand: (3) this supersedes BR-10's "bump the minor version" and CONTEXT.md's minor-bump rule for this
release only; (4) a consumer on the installed 1.0.0 sees no version change, so a version-keyed plugin update
would not offer them this build (unverified; worth checking before go-live); (5) at go-live the owner answers
"go as v1.0.0" — next-version.sh will still propose v0.1.0 and must be overridden. Go-live itself is not given.
Follow-up (business-analyst, 2026-09-19): recorded in `requirements.md` as the "Amendment 2026-09-19
(Q-4)" note at the top, with FR-30, AC-35, §8 "Version" and §8 "Rollback" amended in place (no FR/AC
renumbered, removed or weakened) and the AC-12 "pre-1.1.0" wording reworded. The supersession of
BR-10's minor bump is stated inside requirements.md; product.md is NOT edited. The engineering work is
SHI-24 (eng, open), a sub-issue of SHI-5, amending SHI-19 (left Done). No new question was needed —
the decision and its consequences are fully specified by this Q-4 answer. Consequence (4) — a consumer
on the installed 1.0.0 sees no version change, so a version-keyed plugin update would not offer them
this build — remains unverified and is the owner's call at go-live; SHI-24 does not address it.
Owner clarification (2026-09-19, after the answer above): no one is actively using this yet, so the version
does not matter for now; it only has to be 1.0.0 once all changes are done. Consequences (2) two builds
sharing 1.0.0 and (4) installed-1.0.0 users not being offered this build are therefore moot in practice.
The decision itself is unchanged (this build is v1.0.0; at go-live the owner answers "go as v1.0.0").
