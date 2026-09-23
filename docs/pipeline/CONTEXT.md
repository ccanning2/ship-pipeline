# ship-pipeline — Pipeline context (read by every persona)

Profile: **ship** — a Claude Code plugin / developer-tooling repo. There is no running service, no
database and no hosted environment; the artefact is the plugin itself, consumed by other repos.
The personas are generic; THIS file is what makes them behave correctly here. The product owner owns it.

## Product
- A Claude Code plugin distributed through a plugin marketplace. Users install it once per machine
  (`/plugin install <plugin>@<marketplace>`) and scaffold it into a repo with `/pipeline-init`.
- Audience: developers and solo founders running delivery on their own repos. Not an end-user product.
- Brand: plain, terse, engineering-first. Docs are reference material, not marketing copy.
- Claims that must NOT be made: that the pipeline replaces human review, guarantees a safe deploy,
  or that any persona can approve its own work. Go-live is always the owner's decision.
- User segments: **plugin author** (this repo), **installing developer** (runs `/pipeline-init`),
  **pipeline operator** (runs `/ship` day to day).
- Release channels: README, CHANGELOG.md, the version tag, the GitHub repo description.

## Market
- Competitors to track: Claude Code plugins/skills doing release orchestration, GitHub Actions
  release templates, Backstage-style golden paths, Danger/Release Please style automation.
- Where real signal lives: issues on this repo, Claude Code plugin discussions, users' own pipelines.
- Regulatory notes: none. The plugin handles no personal data. It must never write secrets into a
  scaffolded repo — only placeholder names of secrets and vars.

## Stack & commands
- Language: **Bash** (`#!/usr/bin/env bash`, `set -euo pipefail`). No runtime dependencies beyond
  git, bash and coreutils; `python3` (stdlib `json`, plus `yaml`) is used by the test suite only.
- Agents and commands are **Markdown with YAML frontmatter** (`agents/*.md`, `commands/*.md`);
  `template/` holds the copies scaffolded into a consuming project.
- Tests: `bash tests/pipeline/run-all.sh`, which runs `test_config.sh test_init.sh test_gate.sh
  test_promote.sh test_intake_status.sh test_allow_paths.sh test_guard_merge.sh
  test_doctor.sh test_deploy_scripts.sh` in turn. This is the only test command; there is no separate
  frontend/backend suite. `python-docx`, `pandoc` and `poppler-utils` are **optional**: the
  `intake.sh` document tests skip themselves when they are absent, they do not fail.
- Lint/build: none. Syntax is checked in-suite (`bash -n`); keep every `scripts/**/*.sh` executable.
- Docker: **not applicable.** No image is built or promoted; the promoted artefact is the git sha,
  then the version tag.
- Architecture docs to keep updated: `README.md` (layout + install), `docs/pipeline/BRANCHING.md`,
  `docs/pipeline/TICKETS.md`, `docs/pipeline/CLOUD.md`.
- Version lives in `.claude-plugin/plugin.json`; it must match the `vX.Y.Z` tag cut at go-live.

## Environments (see BRANCHING.md)
- An "environment" here is **a ref people can install from**, not a host: dev ← merge to `master` ·
  qa ← push to `staging` · staging ← same sha · production ← tag `vX.Y.Z`. The URLs in
  `scripts/pipeline/pipeline.env` point at those refs. Every review stage still applies, and the same
  sha still travels the whole path.
- **Verification is done by installing the plugin from the ref into a throwaway git repo** and
  running the flow there. `scripts/deploy/*` and `smoke.sh` are templates shipped to consumers; they
  are not used to release this repo.
- Test data policy: fixtures only, under `mktemp -d`. Tests must never touch the user's real repos,
  tracker or network.

## Project shape (the two capability settings)
Declared in `scripts/pipeline/pipeline.env`; both default to `yes` and are off only for an explicit `no`.
- `PIPELINE_HAS_DEPLOY_ENVS="no"` — there is nothing to deploy to. `promote.sh` performs no deploy
  wait, no staging workflow dispatch and no smoke call. `.github/workflows/deploy.yml` and
  `scripts/deploy/*` stay in the repo as the templates consumers receive; this project does not use
  them to release itself.
- `PIPELINE_START_LEVEL="analysis"` — tickets start with the product owner and business analyst.
  Release notes live in `CHANGELOG.md` and on the version tag.

## Engineering rules
- The six personas stay **project-agnostic**. No product, person, vendor or project-type names in
  `agents/*.md` or `commands/*.md` — the test suite enforces this. The persona files live at
  `agents/*.md` (the `template/` tree holds no personas), mirrored at `.claude/agents/*.md` for this
  repo's own use; **edit both copies together**.
- Everything project-specific belongs in `docs/pipeline/CONTEXT.md` and `RELEASE_CHECKLIST.md`,
  or in a `profiles/<name>/` pair. Never hardcode it into tooling.
- `scripts/init.sh` is **idempotent** and must never overwrite project-owned files (CONTEXT.md,
  RELEASE_CHECKLIST.md, pipeline.env, `.github/workflows/*`, `scripts/deploy/*`, `.claude/settings.json`).
  Tooling paths are refreshed every run. Any new file must be classified into one of the two.
- Changing a tooling path, an agent name or a template filename is a **breaking change for every
  installed project**. Bump the minor version and say so in the release notes.
- `template/` is the source of what gets scaffolded; the plugin's own top-level `agents/` and
  `commands/` are what Claude Code loads when this repo itself is installed as a plugin.
- Stop and ask before: renaming or removing a script in `scripts/pipeline/`, changing the gate's
  pass/fail conditions, changing the branch/tag model, or altering the write-boundary hooks.

## High-risk areas (QA and app specialist focus here)
- `scripts/init.sh` — clobbering a consumer's project-owned files, or a half-applied install when
  it exits early (validate arguments *before* copying anything).
- `scripts/pipeline/gate.sh` and `check-signoff.sh` — a gate that wrongly passes lets unreviewed
  work reach production in every consuming repo.
- `scripts/pipeline/hooks/allow-paths.sh` and `guard-merge.sh` — the write boundaries that stop a
  persona editing code it does not own.
- `scripts/pipeline/promote.sh` and `next-version.sh` — wrong sha or wrong version tag on release.
- Agent frontmatter (`disallowedTools`, `model`, hooks) — a silent typo removes a safety boundary.
- Cross-platform shell: Windows/Git-Bash and macOS BSD tools (`sed -i`, `cmp`, CRLF line endings).

## Open strategic questions (do not assume resolved)
- Whether `scripts/deploy/*` should stay Hetzner/docker-compose specific or become pluggable targets.
- Whether profiles should be distributable separately from the plugin.
- How consumers upgrade tooling safely once their pipeline is live (`/pipeline-init` re-run vs a
  versioned migration step).
