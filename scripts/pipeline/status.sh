#!/usr/bin/env bash
# Show which pipeline gates a ticket currently passes. Usage: status.sh <TICKET> [REF]
set -uo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
[ -n "$ticket" ] || { echo "usage: status.sh <TICKET> [REF]" >&2; exit 1; }
here="$(dirname "$0")"
# Project capabilities come from pipeline.env only (never the environment), same rule as gate.sh.
unset PIPELINE_HAS_DEPLOY_ENVS
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
capability_note() { # <raw value> <what turning it off disables>
  local raw="${1:-}" v
  v="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$v" in
    no) printf 'off (%s)' "$2" ;;
    ""|yes) printf 'on' ;;
    *)  printf "on (unrecognised value '%s' — using the strict default)" "$raw" ;;
  esac
}
echo "Pipeline gates for $ticket"
printf 'Start level: %s\n' "$(printf '%s' "${PIPELINE_START_LEVEL:-analysis}" | tr '[:upper:]' '[:lower:]')"
printf 'Project capabilities: deploy-envs=%s\n' \
  "$(capability_note "${PIPELINE_HAS_DEPLOY_ENVS:-}" 'deploy, dispatch and smoke steps are skipped; promotion still runs')"
next=""
for s in build dev qa staging production; do
  if out="$(bash "$here/gate.sh" "$ticket" "$s" ${2:+"$2"} 2>&1)"; then
    printf '  [x] %-11s %s\n' "$s" "$(echo "$out" | sed -n 's/^DEPLOY_SHA=/sha /p')"
  else
    printf '  [ ] %-11s %s\n' "$s" "$(echo "$out" | head -1 | sed 's/^PIPELINE GATE \[[^]]*\]: //')"
    [ -n "$next" ] || next="$s"
  fi
done
echo "Next gate to clear: ${next:-none (shipped)}"
