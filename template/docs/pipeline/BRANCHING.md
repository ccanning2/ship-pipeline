# Branch & release model

```
feature/<TICKET>-slug ──merge──► master ──► DEV   (image built: ghcr.io/<repo>:<sha>)
                                   │ push same sha
                                staging ──► QA    (same image)
                                   │ dispatch same sha
                                            STAGING (same image)
                                   │ tag vX.Y.Z on that sha
                                            PRODUCTION (image re-tagged :vX.Y.Z and :latest)
```

| Action | Who | Deploys | Gate enforced |
|---|---|---|---|
| Merge ticket branch → `master` | engineer (`promote.sh dev`) | dev; builds the image | `dev`: eng tickets done, no open defects, branch contains latest master |
| Push master sha → `staging` branch | engineer (`promote.sh qa`) | qa | `qa`: dev self-check passed on that sha, no code change since |
| Dispatch same sha → staging env | engineer (`promote.sh staging`) | staging | `staging`: QA passed on that sha, QA defects verified |
| Tag `vX.Y.Z` on that sha | engineer (`promote.sh production`), after the owner's go | production | `production`: sign-off, all defects verified, marketing ready (only if the project has a marketing function and the ticket is user-facing), Go-live + Version set |

Rules:
- **Build once.** The image is built on the way into dev and never rebuilt; every environment runs the identical `:<sha>` image. Production adds the `:vX.Y.Z` tag so any release can be found and redeployed by version.
- **Any code change after the dev deploy re-enters at dev.** Defect fixes go feature branch → master → dev → staging branch → qa → staging.
- **Never rebase or force-push** a pushed branch; merge `master` in instead. `master` and `staging` are protected; the Pipeline Gate check is required on PRs to both.
- **Versions** are semver: feature → minor, bugfix/security/chore → patch (`scripts/pipeline/next-version.sh`); the owner can override at go-live.
- **Rollback**: `scripts/deploy/rollback.sh production` restores the previous tag recorded on the host; or dispatch `deploy.yml` with the previous version's sha.
- **Projects with no deployable environments** (`PIPELINE_HAS_DEPLOY_ENVS="no"` in `pipeline.env`): the table above is unchanged — the same sha still travels `master` → the `staging` branch → the version tag — but `promote.sh` performs no deploy wait, no staging workflow dispatch and no smoke call, and says so in its output. An "environment" is then the ref people install from, and rollback is the previous version tag. The key defaults to `yes`, so an install that never sets it is unaffected.
- The `staging` branch is a pointer, not a place to commit: it always equals some master sha.
