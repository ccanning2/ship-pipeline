#!/usr/bin/env bash
# The one definition of a ticket id, shared by the hook, the gate, intake and both workflows.
# Usage: ticket-id.sh --regex        print the extended regex (from scripts/pipeline/pipeline.env)
#        ticket-id.sh [TEXT...]      print the first ticket id in TEXT (stdin when no TEXT), uppercased;
#                                    exit 1 when there is none
# The regex is PIPELINE_TICKET_REGEX; when that is unset, <TRACKER_TEAM_KEY>-[0-9]+; only with no key
# either, the broad [A-Z][A-Z0-9]+-[0-9]+. An id must stand alone: "xREP-1" and "REP-1x" are not REP-1.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
key="$(printf '%s' "${TRACKER_TEAM_KEY:-}" | tr -cd 'A-Za-z0-9')"
regex="${PIPELINE_TICKET_REGEX:-}"
case "$regex" in -*) regex="";; esac   # an empty team key leaves "-[0-9]+", which is no pattern at all
if [ -z "$regex" ]; then
  if [ -n "$key" ]; then regex="$key-[0-9]+"; else regex='[A-Z][A-Z0-9]+-[0-9]+'; fi
fi
if [ "${1:-}" = --regex ]; then printf '%s\n' "$regex"; exit 0; fi
if [ $# -gt 0 ]; then text="$*"; else text="$(cat)"; fi
id="$(printf '%s\n' "$text" | grep -oiE "(^|[^A-Za-z0-9])($regex)([^A-Za-z0-9]|\$)" | head -1 \
  | sed -E 's/^[^A-Za-z0-9]//; s/[^A-Za-z0-9]$//' | tr '[:lower:]' '[:upper:]')"
[ -n "$id" ] || exit 1
printf '%s\n' "$id"
