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
| SHI-17 | eng | - | - | open | engineer | init.sh / pipeline-init: declare capabilities at install time, scaffold only what the shape needs |
| SHI-18 | eng | - | - | open | engineer | Orchestrator, personas and status.sh: marketing is a project capability, and a skipped stage says so |
| SHI-19 | eng | - | - | open | engineer | Docs and v1.1.0: tell installing developers the settings exist, what the defaults are, how to opt out |
| SHI-20 | eng | - | - | open | engineer | Dogfood: switch this repo onto the new settings and delete the workaround prose |
| SHI-10 | follow-up | - | - | open | the-owner | research.md template ships placeholder text from an unrelated product |
| SHI-11 | follow-up | - | - | open | the-owner | Pluggable deploy targets instead of Hetzner/docker-compose specific scripts |
| SHI-12 | follow-up | - | - | open | the-owner | How existing installs receive new pipeline.env keys (migration step) |
