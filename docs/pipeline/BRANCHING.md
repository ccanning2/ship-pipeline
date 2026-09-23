# Branch & release model

The base branch is `master` and the staging branch is `staging` (`BASE_BRANCH` and `STAGING_BRANCH` in
`scripts/pipeline/pipeline.env`; `bash scripts/pipeline/base-ref.sh` prints them). Every fetch, push and merge goes to the
remote named by `PIPELINE_REMOTE` (default `origin`).

```
feature/<TICKET>-slug ──merge──► master ──► DEV   (image built: <registry>/<repo>:<sha>)
                                   │ push same sha
                                staging ──► QA    (same image)
                                   │ dispatch same sha
                                            STAGING (same image)
                                   │ tag vX.Y.Z on that sha
                                            PRODUCTION (image re-tagged :vX.Y.Z and :latest)
```

| Action | Who | Deploys | Gate enforced |
|---|---|---|---|
| Merge ticket branch → `master` | engineer (`promote.sh dev`) | dev; builds the image | `dev`: eng tickets done, no open defects, branch contains the latest `master` |
| Push `master` sha → `staging` branch | engineer (`promote.sh qa`) | qa | `qa`: dev self-check passed on that sha, no code change since |
| Dispatch same sha → staging env | engineer (`promote.sh staging`) | staging | `staging`: QA passed on that sha, QA defects verified |
| Tag `vX.Y.Z` on that sha | engineer (`promote.sh production`), after the owner's go | production | `production`: sign-off, all defects verified, marketing ready (only if the project has a marketing function and the ticket is user-facing), Go-live + Version set |

Rules:
- **Build once.** The image is built on the way into dev and never rebuilt; every environment runs the identical `:<sha>` image. Production adds the `:vX.Y.Z` tag so any release can be found and redeployed by version.
- **Any code change after the dev deploy re-enters at dev.** Defect fixes go feature branch → `master` → dev → `staging` branch → qa → staging.
- **Never rebase or force-push** a pushed branch; merge `master` in instead. The guard hook refuses an agent's force push or delete of `master`, `staging` or a version tag outright.
- **Enforcement** has two layers, and `bash scripts/pipeline/enforcement.sh` (also `/pipeline-status` and `/pipeline-doctor`) says which one this repository has:
  - *host*: `master` and `staging` are protected (branch protection or a ruleset) and the **Pipeline Gate** check is required on PRs to both. Configure this when the plan allows it.
  - *local hook only*: the host would not require the check. GitHub offers neither branch protection nor rulesets on a free private repository (HTTP 403); Bitbucket Cloud's "require passing builds" is a Premium feature. Then only `scripts/pipeline/hooks/guard-merge.sh` enforces the model. It gates agent tool calls only; a human or another tool can push past it, and CI reports a failing gate without being able to stop the merge.
  - `/pipeline-init` sets the host layer up when the owner allows it (`scripts/pipeline/host.sh protect`): branch protection requiring the `gate` check (GitHub), protected branches plus "Pipelines must succeed" (GitLab), or a "require passing builds" restriction (Bitbucket).
- **Repository maintenance without a ticket** (the install commit, a CI migration, a dependency bump, a config change): push a branch and open a PR/MR. A human reviews it and marks it **infra**, which makes the Pipeline Gate skip the ticket requirement: the `infra` label on GitHub and GitLab, or, on Bitbucket (no PR labels), a source branch named `infra/<anything>`. The request still needs that human to merge it. Agents never mark it, and the guard hook blocks them if they try. The owner may also run such a command in their own terminal: the hook gates agent tool calls only.
- **Versions** are semver: feature → minor, bugfix/security/chore → patch (`scripts/pipeline/next-version.sh`); the owner can override at go-live.
- **Rollback**: `scripts/deploy/rollback.sh production` restores the previous tag recorded on the host; or start the deploy pipeline for production with the previous version's sha (`bash scripts/pipeline/host.sh dispatch production <sha> <ticket> <tag>`).
- **Deploy mode** (`DEPLOY_MODE` in `pipeline.env`): `merge` (the default) deploys on the push itself, as in the table above, and dispatches only staging; `explicit` removes the push and tag triggers from the CI files, and `promote.sh` dispatches every environment right after its gate passes. The gates are the same either way.
- **Projects with no deployable environments** (`PIPELINE_HAS_DEPLOY_ENVS="no"` in `pipeline.env`): the table above is unchanged — the same sha still travels `master` → the `staging` branch → the version tag — but `promote.sh` performs no deploy wait, no staging workflow dispatch and no smoke call, and says so in its output. An "environment" is then the ref people install from, and rollback is the previous version tag. The key defaults to `yes`, so an install that never sets it is unaffected.
- **Deploys are off until the environments exist**: the deploy jobs (`deploy.yml`, `.gitlab/pipeline-deploy.yml` or the Bitbucket deploy step) run only when the repository/CI variable `PIPELINE_DEPLOY_ENABLED` is `true`. `/pipeline-init` sets it when the owner says the hosts and secrets exist.
- The `staging` branch is a pointer, not a place to commit: it always equals some `master` sha.
- **Supported hosts** (`GIT_HOST`, and `GIT_HOST_URL` for a self-hosted one): GitHub with GitHub Actions (`gh`; GitHub Enterprise too), GitLab with GitLab CI (`glab`; self-managed too), and Bitbucket Cloud with Bitbucket Pipelines (REST with an API token; Bitbucket Data Center has no Pipelines, so only its git side works). `promote.sh`, the enforcement check and the doctor reach the host only through `scripts/pipeline/host.sh`. Cloud sessions (docs/pipeline/CLOUD.md) need GitHub.
