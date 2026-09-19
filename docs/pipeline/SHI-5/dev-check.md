# SHI-5 — Dev self-check (engineer)

Result: pass
Environment: dev
Commit: f9cc6aff65942cf711b2117392adcd71e66a459f

> Rework loop 2/3 (re-entry at dev after QA's second round found SHI-25). This project has no host
> (`PIPELINE_HAS_DEPLOY_ENVS="no"`), so "dev" is the `master` ref and the check is done the way CONTEXT.md
> prescribes: install the plugin from the promoted ref into throwaway git repos and run the flow there.
> Installed from `origin/master` @ b934d83, which is the Dev sha above plus the pipeline's own records commit.
> This supersedes the earlier dev checks (2e9552d, 6a0cbbc).

| Check | Result | Notes |
|---|---|---|
| Plugin installs from the ref (`init.sh` runs clean into a fresh repo) | pass | exit 0 |
| Opted out (`--no-deploy-envs --no-marketing`): no `scripts/deploy/*`, no `deploy.yml` | pass | both absent |
| Opted out: `pipeline-gate.yml` still scaffolded; both keys `"no"`; no placeholder left | pass | 2 keys, 0 placeholders |
| `status.sh` reports the capabilities | pass | `deploy-envs=off … marketing=off …` |
| SHI-21: flagless and `--force-tooling` re-runs over the opted-out install | pass | deploy files not recreated; 0 files changed |
| SHI-25: a `no` whose trailing comment holds quotes or apostrophes is honoured | pass | `"no"  # we don't deploy`, `no # it's off`, `no # a " mark`, `NO # It's "fine"`: deploy files not recreated |
| SHI-25 strict side: `"yes"`, `no#x`, `"no"#x`, and `no` followed by `unset KEY` | pass | deploy files created (init resolves ON, as the gate does) |
| SHI-22: `--profile nope` | pass | exits 1; file count unchanged |
| SHI-23: vendor names in `agents/` and `commands/` | pass | none (both scans) |
| Defaults (no flags) behave as before | pass | deploy files present, both keys `"yes"` |
| Version (SHI-24, Q-4) | pass | `plugin.json` 1.0.0; one `### v1.0.0` heading, no `### v1.1.0` |
| `gate.sh SHI-5 dev` and `promote.sh SHI-5 dev` on this repo | pass | fast-forwarded to the SHI-25 fix; no deploy wait (nothing to deploy to) |
| 49-form differential of `init.sh`'s parser against `gate.sh`'s real resolution | pass | 36 agree, 5 init-stricter (harmless), 5 gate-errors, 3 permissive = the documented control-flow limit only |
| `bash -n scripts/init.sh` | pass | clean |

Not run here, by the owner's scoped-re-test decision: `test_init.sh` (QA's two `QA-DEF` and 15 `QA2:` assertions,
about 70 minutes) and the full `run-all.sh` (about 1 h 40 min). The last full run was 711/711 on 6a0cbbc. Since
then the only shipped script that changed is `scripts/init.sh`; QA's own edits to `tests/pipeline/test_config.sh`
(AC-31 scan made word-bounded) and `tests/pipeline/test_init.sh` (+17 assertions) are the only other non-record
changes. QA runs `test_init.sh` in full, plus `test_config.sh` and the differential.
