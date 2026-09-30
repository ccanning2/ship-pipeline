#!/usr/bin/env bash
# The Pipeline Gate for a pull/merge request. Shared by the GitLab and Bitbucket CI files (GitHub Actions does the
# same inline in pipeline-gate.yml).
# Usage: ci-gate.sh <source branch> <title> <target branch> <infra: true|false>
#   A request into the base branch must pass the "dev" gate, into the staging branch the "qa" gate; a request into
#   any other branch passes. infra=true (a human marked it repository maintenance with no ticket) skips the ticket
#   gate but still needs that human to merge it.
set -euo pipefail
src="${1:-}"; title="${2:-}"; target="${3:-}"; infra="${4:-false}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="$(bash "$here/base-ref.sh" --branch)"; stg="$(bash "$here/base-ref.sh" --staging)"
case "$target" in "$base") stage=dev;; "$stg") stage=qa;; *) echo "Not into $base or $stg: no gate."; exit 0;; esac
if [ "$infra" = true ]; then echo "Marked infra: no ticket gate. A human reviews and merges this request."; exit 0; fi
t="$(bash "$here/ticket-id.sh" "$src" "$title")" || {
  echo "No ticket id in the branch name or title (ids match $(bash "$here/ticket-id.sh" --regex)). Repository maintenance with no ticket: a human marks it infra." >&2
  exit 1; }
git fetch -q "$(bash "$here/base-ref.sh" --remote)" "$base" 2>/dev/null || true
bash "$here/status.sh" "$t" || true
PIPELINE_BASE_REF="$(bash "$here/base-ref.sh")" bash "$here/gate.sh" "$t" "$stage"
