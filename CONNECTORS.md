# Connectors

## How tool references work

Plugin files use `~~category` as a placeholder for whatever tool the project uses in that category. For example, `~~code host` means GitHub, GitLab or Bitbucket, whichever `GIT_HOST` in `scripts/pipeline/pipeline.env` names.

The plugin is **tool-agnostic**: the skills and personas describe the work in terms of categories and call one adapter per category (`scripts/pipeline/host.sh`, `scripts/pipeline/tracker.sh`). `/pipeline-init` installs the adapter for the tools you pick, so nothing else in the pipeline names a product.

## CLIs first, connectors as a fallback

Unlike most plugins, this one ships **no `.mcp.json`**. Every category is reached through a CLI or the tool's API, signed in once with `bash scripts/pipeline/connect.sh login`, so a run is scriptable, works in CI and in cloud sessions, and does not depend on a connector being enabled. An MCP connector is used only for a tracker no CLI fits (`TRACKER="connector"`): then `tracker.sh` exits 3 and the caller uses that ~~project tracker connector's tools for the step.

## Connectors for this plugin

| Category | Placeholder | Supported (through) | Setting | Fallback |
|----------|-------------|---------------------|---------|----------|
| Code host | `~~code host` | GitHub (`gh`, Enterprise through `GIT_HOST_URL`), GitLab (`glab`, self-managed through `GIT_HOST_URL`), Bitbucket Cloud (REST with an API token) | `GIT_HOST`, `GIT_HOST_URL` | none |
| Project tracker | `~~project tracker` | Jira (`acli`), Linear (the Linear API), GitHub Issues (`gh`), GitLab issues (`glab`) | `TRACKER`, `TRACKER_URL`, `TRACKER_CLOUD_ID`, `TRACKER_TEAM_KEY` | any tracker's MCP connector (`TRACKER="connector"`) |
| CI/CD | `~~CI/CD` | GitHub Actions, GitLab CI, Bitbucket Pipelines (the Pipeline Gate and deploy files in `template/`) | follows `GIT_HOST`; `DEPLOY_MODE` | none |
| Deploy target | `~~deploy target` | docker compose over SSH (`scripts/deploy/`), or your own deploy script | `DEV_URL` … `PRODUCTION_URL`, `HEALTH_PATH`, `PIPELINE_HAS_DEPLOY_ENVS` | `PIPELINE_HAS_DEPLOY_ENVS="no"`: the refs move, nothing deploys |

To switch a category to another tool, re-run `/pipeline-init` with the new answer (for example `--git-host gitlab` or `--tracker jira`). `/pipeline-doctor` flags an installed adapter that does not match `pipeline.env`.
