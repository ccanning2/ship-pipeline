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
stages="build dev qa staging production"
# The gates and the teams lookups only read, so they run side by side (each gate.sh start-up costs several
# processes, slow on Windows); the results are printed in the usual order. PIPELINE_STATUS_SERIAL=1 runs them in turn.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
run() { # <name> <cmd...>: stdout (and, for a gate, stderr) to $tmp/<name>, exit code to $tmp/<name>.rc
  local n="$1"; shift
  case "$n" in gate-*) "$@" > "$tmp/$n" 2>&1;; *) "$@" > "$tmp/$n";; esac; echo $? > "$tmp/$n.rc"
}
if [ "${PIPELINE_STATUS_SERIAL:-0}" = 1 ]; then
  run teams bash "$here/teams.sh" "$ticket"; run entry bash "$here/teams.sh" "$ticket" --entry
  for s in $stages; do run "gate-$s" bash "$here/gate.sh" "$ticket" "$s" ${2:+"$2"}; done
else
  run teams bash "$here/teams.sh" "$ticket" & run entry bash "$here/teams.sh" "$ticket" --entry &
  for s in $stages; do run "gate-$s" bash "$here/gate.sh" "$ticket" "$s" ${2:+"$2"} & done
  wait
fi
echo "Pipeline gates for $ticket"
printf 'Teams: %s (arrives at %s)\n' "$(cat "$tmp/teams")" "$(cat "$tmp/entry")"
printf 'Project capabilities: deploy-envs=%s\n' \
  "$(capability_note "${PIPELINE_HAS_DEPLOY_ENVS:-}" 'deploy, dispatch and smoke steps are skipped; promotion still runs')"
next=""; cleared=0; total=0
for s in $stages; do
  total=$((total + 1))
  out="$(cat "$tmp/gate-$s")"
  if [ "$(cat "$tmp/gate-$s.rc")" = 0 ]; then
    cleared=$((cleared + 1))
    printf '  [x] %-11s %s\n' "$s" "$(echo "$out" | sed -n 's/^DEPLOY_SHA=/sha /p')"
  else
    printf '  [ ] %-11s %s\n' "$s" "$(echo "$out" | head -1 | sed 's/^PIPELINE GATE \[[^]]*\]: //')"
    [ -n "$next" ] || next="$s"
  fi
done
printf 'Gates cleared: %d of %d (%d%%)\n' "$cleared" "$total" $((cleared * 100 / total))
echo "Next gate to clear: ${next:-none (shipped)}"
