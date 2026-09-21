#!/usr/bin/env bash
# The project's trunk, for agents, workflows and scripts. Never assumes a branch name.
# Usage: base-ref.sh             <remote>/<base branch>, e.g. origin/main (what `git diff X...HEAD` wants)
#        base-ref.sh --branch    <base branch>, e.g. main
#        base-ref.sh --staging   <staging branch>, e.g. staging
#        base-ref.sh --remote    <remote>, e.g. origin
# Values come from scripts/pipeline/pipeline.env (BASE_BRANCH, STAGING_BRANCH, PIPELINE_REMOTE). With no
# BASE_BRANCH there, the remote's default branch (<remote>/HEAD) is used, then a local main or master.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
remote="${PIPELINE_REMOTE:-origin}"
base="${BASE_BRANCH:-}"
if [ -z "$base" ]; then
  base="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"; base="${base#"$remote/"}"
fi
if [ -z "$base" ]; then
  for c in main master; do git rev-parse -q --verify "refs/heads/$c" >/dev/null 2>&1 && { base="$c"; break; }; done
fi
[ -n "$base" ] || base=master
case "${1:-}" in
  --branch) echo "$base";;
  --staging) echo "${STAGING_BRANCH:-staging}";;
  --remote) echo "$remote";;
  "") echo "$remote/$base";;
  *) echo "usage: base-ref.sh [--branch|--staging|--remote]" >&2; exit 1;;
esac
