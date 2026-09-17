#!/usr/bin/env bash
# Show which pipeline gates a ticket currently passes. Usage: status.sh <TICKET> [REF]
set -uo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
[ -n "$ticket" ] || { echo "usage: status.sh <TICKET> [REF]" >&2; exit 1; }
here="$(dirname "$0")"
echo "Pipeline gates for $ticket"
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
