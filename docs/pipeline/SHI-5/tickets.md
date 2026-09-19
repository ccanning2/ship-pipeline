# SHI-5 — Linked tickets (mirror of the tracker)

<!-- Kind: story|eng|defect|marketing|follow-up · Found-in: -|dev|qa|staging · Severity: -|High|Medium|Low
     State: open|in-progress|fixed|verified|done|wontfix|reopened · see docs/pipeline/TICKETS.md -->
| Ticket | Kind | Found-in | Severity | State | Owner | Title |
|---|---|---|---|---|---|---|
| SHI-7 | story | - | - | open | business-analyst | Marketing becomes a project-level capability, not a per-ticket side effect |
| SHI-8 | story | - | - | open | business-analyst | Deployable environments become optional; review stages stay mandatory |
| SHI-9 | story | - | - | open | business-analyst | Safe rollout: defaults for existing installs, init scaffolding, docs, dogfood this repo |
| SHI-13 | eng | - | - | done | engineer | Capability config keys: pipeline.env schema, fail-closed resolution, gate PASS reporting |
| SHI-14 | eng | - | - | done | engineer | Production gate: marketing requirement becomes conditional on the project capability |
| SHI-15 | eng | - | - | done | engineer | Release-blocking proof: a pipeline.env without the new keys behaves identically |
| SHI-16 | eng | - | - | done | engineer | promote.sh: skip deploy wait, workflow dispatch and smoke when the project has no deployable environments |
| SHI-17 | eng | - | - | done | engineer | init.sh / pipeline-init: declare capabilities at install time, scaffold only what the shape needs |
| SHI-18 | eng | - | - | done | engineer | Orchestrator, personas and status.sh: marketing is a project capability, and a skipped stage says so |
| SHI-19 | eng | - | - | done | engineer | Docs and v1.1.0: tell installing developers the settings exist, what the defaults are, how to opt out |
| SHI-20 | eng | - | - | done | engineer | Dogfood: switch this repo onto the new settings and delete the workaround prose |
| SHI-21 | defect | qa | Medium | verified | qa-tester | init.sh: a flagless re-run recreates scripts/deploy/* and deploy.yml in a project whose pipeline.env declares no deployable environments |
| SHI-22 | defect | qa | Low | verified | qa-tester | init.sh: an unknown --profile is rejected only after tooling files have been copied (half-applied install) |
| SHI-23 | defect | qa | Low | verified | qa-tester | commands/pipeline-init.md names a vendor (Hetzner); AC-31 / NFR-10 require none in agents/ or commands/ |
| SHI-24 | eng | - | - | done | engineer | Release version is v1.0.0 (owner decision Q-4): plugin.json, README release notes, AC-35 test |
| SHI-25 | defect | qa | Low | verified | qa-tester | init.sh: the new PIPELINE_HAS_DEPLOY_ENVS parser disagrees with gate.sh/promote.sh (an apostrophe in a trailing comment defeats a "no"; some non-"no" forms are read as no) |
| SHI-10 | follow-up | - | - | open | the-owner | research.md template ships placeholder text from an unrelated product |
| SHI-11 | follow-up | - | - | open | the-owner | Pluggable deploy targets instead of Hetzner/docker-compose specific scripts |
| SHI-12 | follow-up | - | - | open | the-owner | How existing installs receive new pipeline.env keys (migration step) |
