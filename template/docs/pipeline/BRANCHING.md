# Branch & release model

The base branch is `__BASE_BRANCH__` and the staging branch is `__STAGING_BRANCH__` (`BASE_BRANCH` and `STAGING_BRANCH` in
`scripts/pipeline/pipeline.env`; `bash scripts/pipeline/base-ref.sh` prints them). Every fetch, push and merge goes to the
remote named by `PIPELINE_REMOTE` (default `origin`).

```
feature/<TICKET>-slug ──merge──► __BASE_BRANCH__ ──► DEV   (image built: ghcr.io/<repo>:<sha>)
                                   │ push same sha
                                __STAGING_BRANCH__ ──► QA    (same image)
                                   │ dispatch same sha
                                            STAGING (same image)
                                   │ tag vX.Y.Z on that sha
                                            PRODUCTION (image re-tagged :vX.Y.Z and :latest)
```

| Action | Who | Deploys | Gate enforced |
|---|---|---|---|
| Merge ticket branch → `__BASE_BRANCH__` | engineer (`promote.sh dev`) | dev; builds the image | `dev`: eng tickets done, no open defects, branch contains the latest `__BASE_BRANCH__` |
| Push `__BASE_BRANCH__` sha → `__STAGING_BRANCH__` branch | engineer (`promote.sh qa`) | qa | `qa`: dev self-check passed on that sha, no code change since |
| Dispatch same sha → staging env | engineer (`promote.sh staging`) | staging | `staging`: QA passed on that sha, QA defects verified |
| Tag `vX.Y.Z` on that sha | engineer (`promote.sh production`), after the owner's go | production | `production`: sign-off, all defects verified, marketing ready (only if the project has a marketing function and the ticket is user-facing), Go-live + Version set |

Rules:
- **Build once.** The image is built on the way into dev and never rebuilt; every environment runs the identical `:<sha>` image. Production adds the `:vX.Y.Z` tag so any release can be found and redeployed by version.
- **Any code change after the dev deploy re-enters at dev.** Defect fixes go feature branch → `__BASE_BRANCH__` → dev → `__STAGING_BRANCH__` branch → qa → staging.
- **Never rebase or force-push** a pushed branch; merge `__BASE_BRANCH__` in instead. The guard hook refuses an agent's force push or delete of `__BASE_BRANCH__`, `__STAGING_BRANCH__` or a version tag outright.
- **Enforcement** has two layers, and `bash scripts/pipeline/enforcement.sh` (also `/pipeline-status` and `/pipeline-doctor`) says which one this repository has:
  - *host*: `__BASE_BRANCH__` and `__STAGING_BRANCH__` are protected (branch protection or a ruleset) and the **Pipeline Gate** check is required on PRs to both. Configure this when the plan allows it.
  - *local hook only*: GitHub offers neither branch protection nor rulesets on a private repository on the free plan (the API answers HTTP 403). Then only `scripts/pipeline/hooks/guard-merge.sh` enforces the model. It gates agent tool calls only; a human or another tool can push past it, and CI reports a failing gate without being able to stop the merge.
- **Repository maintenance without a ticket** (the install commit, a CI migration, a dependency bump, a config change): push a branch and open a PR. A human reviews it and adds the **`infra`** label, which makes the Pipeline Gate skip the ticket requirement. The PR still needs that human to merge it. Agents never add the label, and the guard hook blocks them if they try. The owner may also run such a command in their own terminal: the hook gates agent tool calls only.
- **Versions** are semver: feature → minor, bugfix/security/chore → patch (`scripts/pipeline/next-version.sh`); the owner can override at go-live.
- **Rollback**: `scripts/deploy/rollback.sh production` restores the previous tag recorded on the host; or dispatch `deploy.yml` with the previous version's sha.
- **Projects with no deployable environments** (`PIPELINE_HAS_DEPLOY_ENVS="no"` in `pipeline.env`): the table above is unchanged — the same sha still travels `__BASE_BRANCH__` → the `__STAGING_BRANCH__` branch → the version tag — but `promote.sh` performs no deploy wait, no staging workflow dispatch and no smoke call, and says so in its output. An "environment" is then the ref people install from, and rollback is the previous version tag. The key defaults to `yes`, so an install that never sets it is unaffected.
- **`deploy.yml` is off until the environments exist**: its jobs run only when the repository variable `PIPELINE_DEPLOY_ENABLED` is `true`.
- The `__STAGING_BRANCH__` branch is a pointer, not a place to commit: it always equals some `__BASE_BRANCH__` sha.
- **Supported hosts:** GitHub with GitHub Actions. `promote.sh`, both workflows and the PR merge path use the GitHub API and `gh`. A repository whose remote, CI or registry is elsewhere (GitLab, for example) must migrate first; `/pipeline-doctor` warns when the remote is not GitHub.
