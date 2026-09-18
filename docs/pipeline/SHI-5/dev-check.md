# SHI-5 — Dev self-check (engineer)

Result: pass
Environment: dev
Commit: 2e9552d30b45ee5db894b3702bd83bdd35c76ce1

> This project has no host (`PIPELINE_HAS_DEPLOY_ENVS="no"`), so "dev" is the `master` ref and the
> check is done the way CONTEXT.md prescribes: install the plugin from the promoted ref into a
> throwaway git repo and run the flow there. Installed from `origin/master` @ 0dcd7b8, which is the
> Dev sha above plus the pipeline's own records commit.

| Check | Result | Notes |
|---|---|---|
| Plugin installs from the ref (`init.sh` runs clean into a fresh repo) | pass | exit 0, no errors |
| Opted out (`--no-deploy-envs --no-marketing`): no `scripts/deploy/*`, no `deploy.yml` | pass | both absent |
| Opted out: `pipeline-gate.yml` still scaffolded | pass | the gate check is not deploy machinery |
| Opted out: both keys written `"no"`, no `__PLACEHOLDER__` left | pass | 0 placeholders |
| `status.sh` reports the capabilities | pass | `deploy-envs=off … marketing=off …` |
| Re-run over the existing install changes nothing (BR-13) | pass | 0 files changed |
| Defaults (no flags) behave as before | pass | deploy files present, both keys `"yes"` |
| `gate.sh SHI-5 dev` on this repo | pass | `marketing=off, deploy-envs=off` |
| `promote.sh SHI-5 dev` on this repo | pass | fast-forwarded master; no deploy wait (nothing to deploy to) |
| Full suite on the branch | pass | 613 passed, 0 failed (baseline 419 / 4 failed) |

Not checked here (by design, and covered later by QA): the `staging`-branch promotion, and installing
through Claude Code's `/plugin install` from the ref (needs an interactive session).
