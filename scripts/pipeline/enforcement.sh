#!/usr/bin/env bash
# How the release model is enforced on the code host. Read-only; always exits 0.
# Usage: enforcement.sh      prints "ENFORCEMENT=<host|local|unknown>" then one line explaining it
#   host     the Pipeline Gate check is required on the base and staging branches (protection or a ruleset)
#   local    only the guard-merge.sh hook enforces it. The hook gates agent tool calls only; a human or
#            another tool can still push past it.
#   unknown  gh is missing or not signed in, so the host could not be asked
# PIPELINE_GH_CMD replaces gh (tests).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh_cmd="${PIPELINE_GH_CMD:-gh}"
base="$(bash "$here/base-ref.sh" --branch)"; stg="$(bash "$here/base-ref.sh" --staging)"
say() { echo "ENFORCEMENT=$1"; echo "$2"; exit 0; }

command -v "${gh_cmd%% *}" >/dev/null 2>&1 || say unknown "Enforcement: unknown (gh is not installed, so branch protection could not be checked)."
$gh_cmd auth status >/dev/null 2>&1 || say unknown "Enforcement: unknown (gh is not signed in; run: gh auth login)."
slug="$($gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$slug" ] || say unknown "Enforcement: unknown (gh cannot see this repository on the code host)."

forbidden=0; missing=""
for b in "$base" "$stg"; do
  checks=""
  if out="$($gh_cmd api "repos/$slug/branches/$b/protection" \
        -q '[.required_status_checks.contexts[]?, .required_status_checks.checks[]?.context] | join(",")' 2>&1)"; then
    checks="$out"
  else
    case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac
  fi
  if out="$($gh_cmd api "repos/$slug/rules/branches/$b" \
        -q '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | join(",")' 2>&1)"; then
    checks="$checks,$out"
  else
    case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac
  fi
  case ",$(printf '%s' "$checks" | tr '[:upper:]' '[:lower:]')," in *gate*) ;; *) missing="$missing $b";; esac
done

[ -z "$missing" ] && say host "Enforcement: host. The Pipeline Gate check is required on $base and $stg."
if [ "$forbidden" = 1 ]; then
  say local "Enforcement: local hook only. The host refused branch protection and rulesets for $slug (HTTP 403: they need a paid plan or a public repository), so nothing on the host requires the Pipeline Gate check. The hook gates agent sessions only; a human or another tool can push past it."
fi
say local "Enforcement: local hook only. No required Pipeline Gate check on:$missing. Add one with branch protection or a ruleset (docs/pipeline/BRANCHING.md). Until then the hook gates agent sessions only; a human or another tool can push past it."
