#!/usr/bin/env bash
# The GitHub code-host adapter, installed as scripts/pipeline/host.sh when GIT_HOST="github" (gh; GitHub Enterprise through GIT_HOST_URL).
# Verbs and test doubles: scripts/pipeline/lib/host-common.sh. To change host, re-run /pipeline-init: it installs the
# matching adapter (the doctor flags an adapter that does not match GIT_HOST).
# adapter: host=github
set -uo pipefail
host=github; pfx=gh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/host-common.sh"

# ---------------------------------------------------------------- GitHub (gh) ----
gh_slug() { $gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || remote_path; }
gh_check() {
  have "$gh_cmd" || { echo "gh is not installed"; return 1; }
  $gh_cmd auth status >/dev/null 2>&1 || { echo "gh is not signed in${GH_HOST:+ to $GH_HOST}"; return 1; }
}
gh_merge() { # branch base title
  local or pr; or="$(gh_slug)"
  pr="$($gh_cmd api "repos/$or/pulls?head=${or%%/*}:$1&state=open" -q '.[0].number' 2>/dev/null || true)"
  if [ -z "$pr" ] || [ "$pr" = null ]; then
    pr="$($gh_cmd api -X POST "repos/$or/pulls" -f title="$3" -f head="$1" -f base="$2" -f body="Pipeline ticket. See docs/pipeline/." -q .number)" || die "could not create a pull request"
  fi
  $gh_cmd api -X PUT "repos/$or/pulls/$pr/merge" -f merge_method=merge -f sha="$(git rev-parse HEAD)" >/dev/null || die "GitHub refused to merge PR #$pr"
}
gh_set_ref() {
  local or; or="$(gh_slug)"
  $gh_cmd api -X PATCH "repos/$or/git/$1" -f sha="$2" -F force=false >/dev/null 2>&1 \
    || $gh_cmd api -X POST "repos/$or/git/refs" -f ref="$1" -f sha="$2" >/dev/null || die "could not update $1"
}
gh_dispatch() { $gh_cmd workflow run "$wf" --ref "$4" -f env="$1" -f sha="$2" -f ticket="$3"; }
gh_wait() { # env sha
  local id=""
  for _ in $(seq 1 "$tries"); do
    id="$($gh_cmd run list --workflow "$wf" --commit "$2" --limit 5 --json databaseId,displayTitle \
          -q "[.[] | select(.displayTitle | test(\"$1\"))][0].databaseId" 2>/dev/null || true)"
    [ -n "$id" ] && [ "$id" != null ] && break; sleep 4
  done
  [ -n "$id" ] && [ "$id" != null ] || die "no '$1' deploy run found for $2"
  echo "host.sh: watching run $id"; $gh_cmd run watch "$id" --exit-status
}
gh_var_get() { $gh_cmd variable get "$1" 2>/dev/null; }
gh_var_set() { $gh_cmd variable set "$1" --body "$2"; }
gh_protect() {
  local or; or="$(gh_slug)"
  printf '{"required_status_checks":{"strict":true,"contexts":["gate"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}' \
    | $gh_cmd api -X PUT "repos/$or/branches/$1/protection" --input - >/dev/null
}
gh_enforcement() {
  local slug forbidden=0 missing="" b checks out
  have "$gh_cmd" || say unknown "Enforcement: unknown (gh is not installed, so branch protection could not be checked)."
  $gh_cmd auth status >/dev/null 2>&1 || say unknown "Enforcement: unknown (gh is not signed in; run /pipeline-init to sign in)."
  slug="$($gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$slug" ] || say unknown "Enforcement: unknown (gh cannot see this repository on the code host)."
  for b in "$base" "$stg"; do
    checks=""
    if out="$($gh_cmd api "repos/$slug/branches/$b/protection" \
          -q '[.required_status_checks.contexts[]?, .required_status_checks.checks[]?.context] | join(",")' 2>&1)"; then
      checks="$out"
    else case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac; fi
    if out="$($gh_cmd api "repos/$slug/rules/branches/$b" \
          -q '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | join(",")' 2>&1)"; then
      checks="$checks,$out"
    else case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac; fi
    case ",$(printf '%s' "$checks" | tr '[:upper:]' '[:lower:]')," in *gate*) ;; *) missing="$missing $b";; esac
  done
  [ -z "$missing" ] && say host "Enforcement: host. The Pipeline Gate check is required on $base and $stg."
  [ "$forbidden" = 1 ] && say local "Enforcement: local hook only. The host refused branch protection and rulesets for $slug (HTTP 403: they need a paid plan or a public repository), so nothing on the host requires the Pipeline Gate check. The hook gates agent sessions only; a human or another tool can push past it."
  say local "Enforcement: local hook only. No required Pipeline Gate check on:$missing. /pipeline-init can add it (docs/pipeline/BRANCHING.md). Until then the hook gates agent sessions only; a human or another tool can push past it."
}
gh_web() { echo "https://${GH_HOST:-github.com}/$(gh_slug)"; }

host_main "$@"
