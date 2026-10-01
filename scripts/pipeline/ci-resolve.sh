#!/usr/bin/env bash
# Which environment a CI run deploys, and whether its gate lets it. Shared by the GitLab and Bitbucket deploy
# pipelines (GitHub Actions does the same inline in deploy.yml).
# Usage: ci-resolve.sh <event> <ref name> [env] [sha] [ticket]
#   event  dispatch  a run started by promote.sh with PIPELINE_ENV / PIPELINE_SHA / PIPELINE_TICKET
#          tag       a pushed version tag           -> production
#          branch    a push to the base or staging branch -> dev or qa
# Prints env=, sha=, ticket=, version= lines (dotenv), or "env=none" when there is nothing to deploy (a push that
# only changed docs/pipeline/, which is how promote.sh syncs its records). Exits 1 when the gate refuses.
set -euo pipefail
event="${1:-}"; ref_name="${2:-}"; in_env="${3:-}"; in_sha="${4:-}"; in_ticket="${5:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base_ref="$(bash "$here/base-ref.sh")"
git fetch -q "$(bash "$here/base-ref.sh" --remote)" "$(bash "$here/base-ref.sh" --branch)" 2>/dev/null || true
case "$event" in
  dispatch)
    env="$in_env"; sha="$(git rev-parse "${in_sha:-HEAD}^{commit}")"; ticket="$(printf '%s' "$in_ticket" | tr '[:lower:]' '[:upper:]')";;
  tag)
    env=production; sha="$(git rev-parse "$ref_name^{commit}")"
    ticket="$(git tag -l --format='%(contents:subject)' "$ref_name" | bash "$here/ticket-id.sh" || true)";;
  branch)
    [ "$ref_name" = "$(bash "$here/base-ref.sh" --staging)" ] && env=qa || env=dev
    sha="$(git rev-parse HEAD)"; ticket=""
    if git rev-parse -q --verify HEAD~1 >/dev/null && [ -z "$(git diff --name-only HEAD~1 HEAD | grep -v '^docs/pipeline/' || true)" ]; then
      echo "env=none"; exit 0
    fi;;
  *) echo "usage: ci-resolve.sh <dispatch|tag|branch> <ref name> [env] [sha] [ticket]" >&2; exit 1;;
esac
case "$env" in dev|qa|staging|production) ;; *) echo "ci-resolve: unknown environment '$env'" >&2; exit 1;; esac
# ticket id: from the input or tag, else from the recent commit messages (merge commits carry the branch name)
[ -n "$ticket" ] || ticket="$(git log -20 --format=%s%n%b "$sha" | bash "$here/ticket-id.sh" || true)"
[ -n "$ticket" ] || { echo "ci-resolve: no ticket id found for $sha" >&2; exit 1; }
# records (Dev/QA/Staging/Go-live) are synced to the base branch by promote.sh; the pushed sha predates them
out="$(PIPELINE_DOCS_REF="$base_ref" bash "$here/gate.sh" "$ticket" "$env" "$sha")"; echo "$out" >&2
expected="$(echo "$out" | sed -n 's/^DEPLOY_SHA=//p')"
[ "$expected" = "$sha" ] || { echo "ci-resolve: the gate expects $expected for $env, got $sha" >&2; exit 1; }
version="$(echo "$out" | sed -n 's/^VERSION=//p')"
if [ "$env" = production ] && [ "$event" = tag ] && [ "$version" != "$ref_name" ]; then
  echo "ci-resolve: tag $ref_name does not match releases.md Version $version" >&2; exit 1
fi
printf 'env=%s\nsha=%s\nticket=%s\nversion=%s\n' "$env" "$sha" "$ticket" "$version"
