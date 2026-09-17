#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash). Enforces the branch/tag release model:
#   push/merge into BASE_BRANCH (master)   -> the ticket must pass the "dev" gate
#   push into STAGING_BRANCH (staging)     -> "qa" gate
#   push of a tag vX.Y.Z / gh release      -> "production" gate
# Exit 2 blocks (stderr shown to Claude). PIPELINE_BYPASS=1 lets a command through (announced).
set -uo pipefail
input="$(cat)"
if command -v jq >/dev/null 2>&1; then cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else cmd="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"; fi
[ -n "$cmd" ] || exit 0
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"; cd "$project" 2>/dev/null || exit 0
# shellcheck disable=SC1091
[ -f scripts/pipeline/pipeline.env ] && source scripts/pipeline/pipeline.env
base="${BASE_BRANCH:-master}"; stg="${STAGING_BRANCH:-staging}"
regex="${PIPELINE_TICKET_REGEX:-[A-Z][A-Z0-9]+-[0-9]+}"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

stage=""
is() { printf '%s' "$cmd" | grep -Eq "$1"; }
tok='(^|[[:space:];&|(])'
if is "${tok}gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)" || is "${tok}gh[[:space:]]+api([[:space:]].*)?pulls/[0-9]+/merge"; then stage=dev
elif is "${tok}gh[[:space:]]+release[[:space:]]+create([[:space:]]|$)"; then stage=production
elif is "${tok}git[[:space:]]+push([[:space:]]|$)"; then
  if is "${tok}git[[:space:]]+push[[:space:]].*(--tags|refs/tags/|[[:space:]:]v[0-9]+\.[0-9]+\.[0-9]+([[:space:];&|)]|$))"; then stage=production
  elif is "(^|[[:space:]:+])(refs/heads/)?$stg([[:space:];&|)]|$)"; then stage=qa
  elif is "(^|[[:space:]:+])(refs/heads/)?$base([[:space:];&|)]|$)"; then stage=dev
  elif [ "$branch" = "$base" ]; then stage=dev
  elif [ "$branch" = "$stg" ]; then stage=qa
  fi
elif [ "$branch" = "$base" ] && is "${tok}git[[:space:]]+merge([[:space:]]|$)"; then stage=dev
elif [ "$branch" = "$stg" ] && is "${tok}git[[:space:]]+merge([[:space:]]|$)"; then stage=qa
fi
[ -n "$stage" ] || exit 0

if [ "${PIPELINE_BYPASS:-0}" = 1 ]; then echo "PIPELINE GATE: bypassed via PIPELINE_BYPASS=1 for: $cmd" >&2; exit 0; fi

ticket="$(printf '%s' "$cmd" | grep -oiE "$regex" | head -1 || true)"
[ -n "$ticket" ] || ticket="$(printf '%s' "$branch" | grep -oiE "$regex" | head -1 || true)"
[ -n "$ticket" ] || ticket="$(printf '%s' "${PIPELINE_TICKET:-}" | grep -oiE "$regex" | head -1 || true)"
[ -n "$ticket" ] || ticket="$(grep -oiE "$regex" "$project/.claude/.pipeline-ticket" 2>/dev/null | head -1 || true)"
[ -n "$ticket" ] || { echo "PIPELINE GATE: blocked '$cmd' — no ticket id found in the command, branch '$branch', PIPELINE_TICKET or .claude/.pipeline-ticket. Run /ship <TICKET>." >&2; exit 2; }

# if the command names a ref carrying the ticket id (e.g. `git merge feature/REP-1-x`), gate that ref
ref=""; set -f
for t in $cmd; do t="${t%%:*}"; if printf '%s' "$t" | grep -qiE "$regex" && git rev-parse --verify -q "${t}^{commit}" >/dev/null 2>&1; then ref="$t"; break; fi; done
set +f
if ! out="$(bash "$project/scripts/pipeline/gate.sh" "$ticket" "$stage" $ref 2>&1)"; then
  echo "$out" >&2; echo "PIPELINE GATE: blocked '$cmd' ($stage gate). Use /ship $ticket, which promotes through scripts/pipeline/promote.sh." >&2; exit 2
fi
exit 0
