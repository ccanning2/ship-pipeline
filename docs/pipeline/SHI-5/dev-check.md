# SHI-5 — Dev self-check (engineer)

Result: pass
Environment: dev
Commit: 6a0cbbcb0dc18ad251e3df9189534888c78a4a3e

> Rework loop 1/3 (re-entry at dev after QA failed the first build). This project has no host
> (`PIPELINE_HAS_DEPLOY_ENVS="no"`), so "dev" is the `master` ref and the check is done the way
> CONTEXT.md prescribes: install the plugin from the promoted ref into throwaway git repos and run the
> flow there. Installed from `origin/master` @ c2f7126, which is the Dev sha above plus the pipeline's own
> records commit. The first dev check (sha 2e9552d) is superseded by this one.

| Check | Result | Notes |
|---|---|---|
| Plugin installs from the ref (`init.sh` runs clean into a fresh repo) | pass | exit 0 |
| Opted out (`--no-deploy-envs --no-marketing`): no `scripts/deploy/*`, no `deploy.yml` | pass | both absent |
| Opted out: `pipeline-gate.yml` still scaffolded; both keys `"no"`; no placeholder left | pass | 2 keys, 0 placeholders |
| `status.sh` reports the capabilities | pass | `deploy-envs=off … marketing=off …` |
| SHI-21: flagless re-run and `--force-tooling` re-run over the opted-out install | pass | deploy files not recreated; 0 files changed |
| SHI-22: `--profile nope` | pass | exits 1; file count unchanged (nothing created) |
| SHI-23: vendor names in `agents/` and `commands/` | pass | none |
| Defaults (no flags) behave as before | pass | deploy files present, both keys `"yes"` |
| Version (SHI-24, owner decision Q-4) | pass | `plugin.json` 1.0.0; one `### v1.0.0` heading, no `### v1.1.0` |
| `gate.sh SHI-5 dev` and `promote.sh SHI-5 dev` on this repo | pass | fast-forwarded to the reworked build; no deploy wait (nothing to deploy to) |
| `test_config.sh` | pass | 162 passed, 0 failed |
| `test_init.sh` | pass | 120 passed, 0 failed (includes QA's five QA-DEF assertions for SHI-21/22) |

Not checked here, and why: the remaining suites (`test_gate`, `test_promote`, `test_intake_status`,
`test_allow_paths`, `test_guard_merge`, `test_deploy_scripts`) were not re-run in one piece after the rework
because the full run was killed twice for low memory; they were last green on the QA sha (613/613) and QA
re-runs them. Also not checked: installing through Claude Code's `/plugin install` (needs an interactive session).
