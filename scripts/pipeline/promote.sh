#!/usr/bin/env bash
# Promote a ticket's build. Usage: promote.sh <TICKET> <dev|qa|staging|production>
#   dev         merge ticket branch -> the base branch (deploys dev, builds image <registry>:<sha>)
#   qa          push the dev sha to the staging branch (deploys qa)
#   staging     dispatch the same sha to the staging environment
#   production  create tag vX.Y.Z on the sha (deploys production; image re-tagged with the version)
# Each step: gate -> promote -> wait for the deploy -> smoke -> record in releases.md -> commit (+push branch).
# PIPELINE_HAS_DEPLOY_ENVS="no" in pipeline.env (project-level only) drops the deploy wait, the staging
# workflow dispatch and the smoke call; the sha still travels the base branch -> the staging branch -> the version tag.
# Branches and the remote come from pipeline.env (BASE_BRANCH, STAGING_BRANCH, PIPELINE_REMOTE; see base-ref.sh).
# Overrides for tests / other hosts:
#   PIPELINE_DEPLOY_CMD  "cmd" run as: cmd <env> <sha> <ticket>   (replaces dispatching/waiting on the code host's CI)
#   PIPELINE_SMOKE_CMD   "cmd" run as: cmd <url>
#   PIPELINE_NO_PUSH=1   skips pushes (local refs still move). The code host is reached through host.sh (GIT_HOST).
set -euo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"; env="${2:-}"
[ -n "$ticket" ] || { echo "usage: promote.sh <TICKET> <dev|qa|staging|production>" >&2; exit 1; }
case "$env" in dev) label=Dev; url_var=DEV_URL;; qa) label=QA; url_var=QA_URL;; staging) label=Staging; url_var=STAGING_URL;; production) label=Production; url_var=PRODUCTION_URL;;
  *) echo "usage: promote.sh <TICKET> <dev|qa|staging|production>" >&2; exit 1;; esac
root="$(git rev-parse --show-toplevel)"; cd "$root"
# Project capabilities are project-level settings, never per-run overrides (see gate.sh).
unset PIPELINE_HAS_DEPLOY_ENVS
# shellcheck disable=SC1091
source scripts/pipeline/pipeline.env
capability() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" in no) echo no;; *) echo yes;; esac; }
has_deploy_envs="$(capability "${PIPELINE_HAS_DEPLOY_ENVS:-}")"
deploys() { [ "$has_deploy_envs" = yes ]; }
# progress suffix: "(dev deploy)" normally, or why nothing was deployed
note() { if deploys; then printf '(%s deploy)' "$1"; else printf '(no deploy: project has no deployable environments)'; fi; }
base="$(bash scripts/pipeline/base-ref.sh --branch)"; stg="$(bash scripts/pipeline/base-ref.sh --staging)"; url="${!url_var:-}"
remote="$(bash scripts/pipeline/base-ref.sh --remote)"
dir="docs/pipeline/$ticket"; rel="$dir/releases.md"
nopush="${PIPELINE_NO_PUSH:-0}"
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "$base" ] || [ "$branch" = "$stg" ]; then echo "PROMOTE: run from the ticket branch, not $branch" >&2; exit 1; fi
[ -z "$(git status --porcelain)" ] || { echo "PROMOTE: working tree not clean; commit first" >&2; exit 1; }

gate_out="$(bash scripts/pipeline/gate.sh "$ticket" "$env")" || exit 1
echo "$gate_out" | grep -vE '^(DEPLOY_SHA|VERSION)='
sha="$(echo "$gate_out" | sed -n 's/^DEPLOY_SHA=//p')"; version="$(echo "$gate_out" | sed -n 's/^VERSION=//p')"

push() { [ "$nopush" = 1 ] || git push -q "$@"; }
push -u "$remote" "$branch" 2>/dev/null || true
pr_mode=0; { [ "${CLAUDE_CODE_REMOTE:-}" = true ] || [ "${PIPELINE_MERGE_MODE:-}" = pr ]; } && pr_mode=1
host() { bash scripts/pipeline/host.sh "$@"; }
merge_branch_to_base() { # merges the ticket branch into the base branch (docs and/or code); leaves the branch containing it
  if [ "$pr_mode" = 1 ]; then
    host merge "$branch" "$base" "$ticket: ship" || { echo "PROMOTE: the code host refused the merge into $base" >&2; return 1; }
    git fetch -q "$remote" "$base" 2>/dev/null || true; git merge -q --no-edit "$remote/$base" 2>/dev/null || true
  else
    if [ "$nopush" = 1 ]; then git update-ref "refs/heads/$base" HEAD; else git push -q "$remote" "HEAD:$base" || { echo "PROMOTE: fast-forward of $base rejected; merge $base in and retry" >&2; return 1; }; fi
  fi
}
set_remote_ref() { # <refs/heads/x|refs/tags/x> <sha> — branch/tag updates; API in cloud sessions (direct pushes are limited there)
  if [ "$nopush" = 1 ]; then git update-ref "$1" "$2"; return; fi
  if [ "$pr_mode" = 1 ]; then host set-ref "$1" "$2" || { echo "PROMOTE: could not update $1" >&2; return 1; }
  else git push -q "$remote" "$2:$1" || { echo "PROMOTE: push to $1 rejected" >&2; return 1; }; fi
}
# DEPLOY_MODE: "merge" (default) -> the push/tag itself starts dev, qa and production deploys and staging is dispatched;
# "explicit" -> nothing deploys on a push: every environment is dispatched here, after its gate.
deploy_mode="$(printf '%s' "${DEPLOY_MODE:-merge}" | tr '[:upper:]' '[:lower:]')"
deploy() { # <env> <ref to run the pipeline on>
  deploys || return 0                       # no deployable environments: nothing to deploy or wait for
  if [ -n "${PIPELINE_DEPLOY_CMD:-}" ]; then $PIPELINE_DEPLOY_CMD "$1" "$sha" "$ticket"; return; fi
  if [ "$deploy_mode" = explicit ] || [ "$1" = staging ]; then
    host dispatch "$1" "$sha" "$ticket" "$2" || return 1
    sleep "${PIPELINE_DISPATCH_SETTLE:-6}"
  fi
  host wait "$1" "$sha" "$2"
}

case "$env" in
  dev)
    merge_branch_to_base || exit 1
    sha="$(git rev-parse HEAD)"
    echo "PROMOTE [$ticket]: $base -> $sha $(note dev)"
    deploy dev "$base" || { echo "PROMOTE: dev deploy failed (see the pipeline log on the code host)" >&2; exit 1; } ;;
  qa)
    set_remote_ref "refs/heads/$stg" "$sha" || exit 1
    echo "PROMOTE [$ticket]: $stg -> $sha $(note qa)"
    deploy qa "$stg" || { echo "PROMOTE: qa deploy failed" >&2; exit 1; } ;;
  staging)
    echo "PROMOTE [$ticket]: $stg -> $sha $(note staging)"
    deploy staging "$stg" || { echo "PROMOTE: staging deploy failed" >&2; exit 1; } ;;
  production)
    if git rev-parse -q --verify "refs/tags/$version^{commit}" >/dev/null 2>&1; then
      [ "$(git rev-parse "$version^{commit}")" = "$sha" ] || { echo "PROMOTE: tag $version exists on another commit" >&2; exit 1; }
    else
      git tag -a "$version" "$sha" -m "$PROJECT_NAME $version ($ticket)"
    fi
    set_remote_ref "refs/tags/$version" "$sha" || exit 1
    echo "PROMOTE [$ticket]: tagged $version on $sha $(note production)"
    deploy production "$version" || { echo "PROMOTE: production deploy failed; roll back: bash scripts/deploy/rollback.sh production" >&2; exit 1; } ;;
esac

if deploys; then
  smoke="${PIPELINE_SMOKE_CMD:-bash scripts/deploy/smoke.sh}"
  if ! $smoke "$url"; then
    echo "PROMOTE: smoke test failed on $env ($url)" >&2
    [ "$env" = production ] && echo "PROMOTE: roll back now: bash scripts/deploy/rollback.sh production" >&2
    exit 1
  fi
fi

[ -f "$rel" ] || cp docs/pipeline/_templates/releases.md "$rel"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; line="$label: $sha $stamp${version:+ $version}"
if grep -qE "^$label:" "$rel"; then sed -i.bak -E "s|^$label:.*|$line|" "$rel" && rm -f "$rel.bak"; else echo "$line" >> "$rel"; fi
echo "- $stamp $env <- $sha${version:+ ($version)}" >> "$dir/deploy-history.md"
git add "$rel" "$dir/deploy-history.md"; git commit -qm "pipeline($ticket): deployed $sha to $env${version:+ as $version}"
push "$remote" "$branch"
merge_branch_to_base || echo "PROMOTE: warning — could not sync pipeline docs to $base; CI gates read docs from $base" >&2
echo "PROMOTE [$ticket]: $env now runs $sha${version:+ ($version)}"
