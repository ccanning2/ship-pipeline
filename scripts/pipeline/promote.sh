#!/usr/bin/env bash
# Promote a ticket's build. Usage: promote.sh <TICKET> <dev|qa|staging|production>
#   dev         merge ticket branch -> master (deploys dev, builds image <registry>:<sha>)
#   qa          push the dev sha to the staging branch (deploys qa)
#   staging     dispatch the same sha to the staging environment
#   production  create tag vX.Y.Z on the sha (deploys production; image re-tagged with the version)
# Each step: gate -> promote -> wait for the deploy -> smoke -> record in releases.md -> commit (+push branch).
# Overrides for tests / other hosts:
#   PIPELINE_DEPLOY_CMD  "cmd" run as: cmd <env> <sha> <ticket>   (replaces waiting on GitHub Actions)
#   PIPELINE_SMOKE_CMD   "cmd" run as: cmd <url>
#   PIPELINE_GH_CMD      gh replacement;  PIPELINE_NO_PUSH=1 skips pushes (local refs still move)
set -euo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"; env="${2:-}"
[ -n "$ticket" ] || { echo "usage: promote.sh <TICKET> <dev|qa|staging|production>" >&2; exit 1; }
case "$env" in dev) label=Dev; url_var=DEV_URL;; qa) label=QA; url_var=QA_URL;; staging) label=Staging; url_var=STAGING_URL;; production) label=Production; url_var=PRODUCTION_URL;;
  *) echo "usage: promote.sh <TICKET> <dev|qa|staging|production>" >&2; exit 1;; esac
root="$(git rev-parse --show-toplevel)"; cd "$root"
# shellcheck disable=SC1091
source scripts/pipeline/pipeline.env
base="${BASE_BRANCH:-master}"; stg="${STAGING_BRANCH:-staging}"; url="${!url_var}"
dir="docs/pipeline/$ticket"; rel="$dir/releases.md"
gh_cmd="${PIPELINE_GH_CMD:-gh}"; nopush="${PIPELINE_NO_PUSH:-0}"
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "$base" ] || [ "$branch" = "$stg" ]; then echo "PROMOTE: run from the ticket branch, not $branch" >&2; exit 1; fi
[ -z "$(git status --porcelain)" ] || { echo "PROMOTE: working tree not clean; commit first" >&2; exit 1; }

gate_out="$(bash scripts/pipeline/gate.sh "$ticket" "$env")" || exit 1
echo "$gate_out" | grep -vE '^(DEPLOY_SHA|VERSION)='
sha="$(echo "$gate_out" | sed -n 's/^DEPLOY_SHA=//p')"; version="$(echo "$gate_out" | sed -n 's/^VERSION=//p')"

push() { [ "$nopush" = 1 ] || git push -q "$@"; }
push -u origin "$branch" 2>/dev/null || true
pr_mode=0; { [ "${CLAUDE_CODE_REMOTE:-}" = true ] || [ "${PIPELINE_MERGE_MODE:-}" = pr ]; } && pr_mode=1
repo_slug() { $gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || git remote get-url origin | sed -E 's#(git@|https://)([^/:]+)[/:]##; s#\.git$##'; }
merge_branch_to_master() { # merges the ticket branch into master (docs and/or code); leaves the branch containing master
  if [ "$pr_mode" = 1 ]; then
    local or pr; or="$(repo_slug)"
    pr="$($gh_cmd api "repos/$or/pulls?head=${or%%/*}:$branch&state=open" -q '.[0].number' 2>/dev/null || true)"
    if [ -z "$pr" ] || [ "$pr" = null ]; then
      pr="$($gh_cmd api -X POST "repos/$or/pulls" -f title="$ticket: ship" -f head="$branch" -f base="$base" -f body="Pipeline ticket $ticket. See docs/pipeline/$ticket/." -q .number)" || { echo "PROMOTE: could not create PR" >&2; return 1; }
    fi
    $gh_cmd api -X PUT "repos/$or/pulls/$pr/merge" -f merge_method=merge -f sha="$(git rev-parse HEAD)" >/dev/null || { echo "PROMOTE: GitHub refused to merge PR #$pr" >&2; return 1; }
    git fetch -q origin "$base" 2>/dev/null || true; git merge -q --no-edit "origin/$base" 2>/dev/null || true
  else
    if [ "$nopush" = 1 ]; then git update-ref "refs/heads/$base" HEAD; else git push -q origin "HEAD:$base" || { echo "PROMOTE: fast-forward of $base rejected; merge $base in and retry" >&2; return 1; }; fi
  fi
}
set_remote_ref() { # <refs/heads/x|refs/tags/x> <sha> — branch/tag updates; API in cloud sessions (direct pushes are limited there)
  if [ "$nopush" = 1 ]; then git update-ref "$1" "$2"; return; fi
  if [ "$pr_mode" = 1 ]; then
    local or; or="$(repo_slug)"
    $gh_cmd api -X PATCH "repos/$or/git/$1" -f sha="$2" -F force=false >/dev/null 2>&1 \
      || $gh_cmd api -X POST "repos/$or/git/refs" -f ref="$1" -f sha="$2" >/dev/null || { echo "PROMOTE: could not update $1" >&2; return 1; }
  else
    git push -q origin "$2:$1" || { echo "PROMOTE: push to $1 rejected" >&2; return 1; }
  fi
}

wait_for_deploy() { # <env> <sha>
  if [ -n "${PIPELINE_DEPLOY_CMD:-}" ]; then $PIPELINE_DEPLOY_CMD "$1" "$2" "$ticket"; return; fi
  local id=""
  for _ in $(seq 1 45); do
    id="$($gh_cmd run list --workflow "$DEPLOY_WORKFLOW" --commit "$2" --limit 5 --json databaseId,displayTitle \
          -q "[.[] | select(.displayTitle | test(\"$1\"))][0].databaseId" 2>/dev/null || true)"
    [ -n "$id" ] && [ "$id" != null ] && break; sleep 4
  done
  [ -n "$id" ] && [ "$id" != null ] || { echo "PROMOTE: no '$1' deploy run found for $2" >&2; return 1; }
  echo "PROMOTE: watching run $id"; $gh_cmd run watch "$id" --exit-status
}

case "$env" in
  dev)
    merge_branch_to_master || exit 1
    sha="$(git rev-parse HEAD)"
    echo "PROMOTE [$ticket]: $base -> $sha (dev deploy)"
    wait_for_deploy dev "$sha" || { echo "PROMOTE: dev deploy failed (gh run view --log-failed)" >&2; exit 1; } ;;
  qa)
    set_remote_ref "refs/heads/$stg" "$sha" || exit 1
    echo "PROMOTE [$ticket]: $stg -> $sha (qa deploy)"
    wait_for_deploy qa "$sha" || { echo "PROMOTE: qa deploy failed" >&2; exit 1; } ;;
  staging)
    if [ -n "${PIPELINE_DEPLOY_CMD:-}" ]; then $PIPELINE_DEPLOY_CMD staging "$sha" "$ticket"; else
      $gh_cmd workflow run "$DEPLOY_WORKFLOW" --ref "$stg" -f env=staging -f sha="$sha" -f ticket="$ticket" || exit 1
      sleep 6; wait_for_deploy staging "$sha" || { echo "PROMOTE: staging deploy failed" >&2; exit 1; }
    fi ;;
  production)
    if git rev-parse -q --verify "refs/tags/$version^{commit}" >/dev/null 2>&1; then
      [ "$(git rev-parse "$version^{commit}")" = "$sha" ] || { echo "PROMOTE: tag $version exists on another commit" >&2; exit 1; }
    else
      git tag -a "$version" "$sha" -m "$PROJECT_NAME $version ($ticket)"
    fi
    set_remote_ref "refs/tags/$version" "$sha" || exit 1
    echo "PROMOTE [$ticket]: tagged $version on $sha (production deploy)"
    wait_for_deploy production "$sha" || { echo "PROMOTE: production deploy failed; roll back: bash scripts/deploy/rollback.sh production" >&2; exit 1; } ;;
esac

smoke="${PIPELINE_SMOKE_CMD:-bash scripts/deploy/smoke.sh}"
if ! $smoke "$url"; then
  echo "PROMOTE: smoke test failed on $env ($url)" >&2
  [ "$env" = production ] && echo "PROMOTE: roll back now: bash scripts/deploy/rollback.sh production" >&2
  exit 1
fi

[ -f "$rel" ] || cp docs/pipeline/_templates/releases.md "$rel"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; line="$label: $sha $stamp${version:+ $version}"
if grep -qE "^$label:" "$rel"; then sed -i.bak -E "s|^$label:.*|$line|" "$rel" && rm -f "$rel.bak"; else echo "$line" >> "$rel"; fi
echo "- $stamp $env <- $sha${version:+ ($version)}" >> "$dir/deploy-history.md"
git add "$rel" "$dir/deploy-history.md"; git commit -qm "pipeline($ticket): deployed $sha to $env${version:+ as $version}"
push origin "$branch"
merge_branch_to_master || echo "PROMOTE: warning — could not sync pipeline docs to $base; CI gates read docs from $base" >&2
echo "PROMOTE [$ticket]: $env now runs $sha${version:+ ($version)}"
