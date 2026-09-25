#!/usr/bin/env bash
# The /ship status board: where a ticket is in the workflow and who is busy with what, in a dozen lines.
# Usage: board.sh <TICKET>                         print the board
#        board.sh <TICKET> --watch [SECONDS]       redraw it every SECONDS (default 3) until Ctrl-C; for a second
#                                                  terminal, or the pane --pane opens
#        board.sh <TICKET> --pane                  inside tmux: open a side pane that watches the board; elsewhere
#                                                  print the command to run in a second terminal
#        board.sh <TICKET> now <persona> <doing>   record who is busy and with what (one short line)
#        board.sh <TICKET> handoff <from> <to> <reason>   record a handoff (one short line, no reasoning)
#        board.sh --all                            one line per ticket in flight
# The stages come from docs/pipeline/<TICKET>/STATUS.md, the environments from releases.md, open defects from
# tickets.md. "now" and "handoff" lines go to .claude/.pipeline-activity/<TICKET>.log: live state, not committed.
# PIPELINE_BOARD_ASCII=1 draws with plain ASCII; colour is used only on a terminal (NO_COLOR turns it off).
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "board: not inside a git repository" >&2; exit 1; }
cd "$root"
act_dir=.claude/.pipeline-activity
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${PIPELINE_BOARD_ASCII:-0}" = 1 ]; then I_DONE='[x]'; I_NOW='[>]'; I_TODO='[ ]'; I_SKIP='[-]'; I_STOP='[!]'; RULE='-'; ARROW='->'
else I_DONE='✓'; I_NOW='▶'; I_TODO='·'; I_SKIP='–'; I_STOP='!'; RULE='─'; ARROW='→'; fi
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; RD=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
else B=; D=; G=; Y=; RD=; C=; N=; fi
line() { local i s=""; for ((i=0; i<80; i++)); do s="$s$RULE"; done; printf '%s%s%s\n' "$D" "$s" "$N"; }
stamp() { date +%H:%M; }

record() { # <TICKET> <kind> <text...>
  mkdir -p "$act_dir"; local t="$1" k="$2"; shift 2
  printf '%s\t%s\t%s\n' "$(stamp)" "$k" "$(printf '%s ' "$@" | tr '\t\n' '  ' | sed 's/ *$//')" >> "$act_dir/$t.log"
}

draw() { # <TICKET>: a handful of processes in all (each one is slow on Windows), so --watch stays light
  local t="$1" d="docs/pipeline/$1" title level now="" kind stage owner doing icon col envs open h txt
  [ -d "$d" ] || { echo "board: no pipeline folder for $t (run /ship $t)"; return 1; }
  title="$(awk 'f && NF { sub(/^#+ */,""); print; exit } /^---$/ { f=1 }' "$d/brief.md" 2>/dev/null)"
  # the teams: the ticket's own choice (STATUS.md), else the project's (PIPELINE_TEAMS, else the older start level)
  level="$(awk -F'"' 'FNR==NR { if (/^Teams:/) { v=$0; sub(/^Teams: */,"",v); sub(/ *\(.*$/,"",v); if (v !~ /^(project|<.*)?$/) { t=v } } next }
    /^PIPELINE_TEAMS=/ { p=$2 } /^PIPELINE_START_LEVEL=/ { l="from " $2 }
    END { print (t ? t : (p ? p : l)) }' "$d/STATUS.md" scripts/pipeline/pipeline.env 2>/dev/null)"
  [ -f "$act_dir/$t.log" ] && now="$(awk -F'\t' '$2=="now" { l=$3 } END { print l }' "$act_dir/$t.log")"
  printf '%s%s%s  %.40s%s\n' "$B" "$t" "$N" "${title:-}" "${level:+   ${D}teams: $level$N}"
  line
  # one row per stage: kind <TAB> stage <TAB> owner <TAB> what is happening (only for the current or a stopped stage)
  while IFS=$'\t' read -r kind stage owner doing; do
    case "$kind" in
      done) icon="$I_DONE"; col="$G";; skip) icon="$I_SKIP"; col="$D";; now) icon="$I_NOW"; col="$Y";;
      stop) icon="$I_STOP"; col="$RD";; *) icon="$I_TODO"; col="$D";;
    esac
    printf ' %s%s %-11s %-31.31s%s %.40s\n' "$col" "$icon" "$stage" "$owner" "$N" "$doing"
  done < <(awk -F'|' -v now="$now" '
    function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
    /^\|/ {
      stage=trim($3); owner=trim($4); st=tolower(trim($5)); sub(/ *\(.*$/, "", owner); gsub(/ *⇄ */, "/", owner)
      if (stage == "" || stage == "Stage" || stage ~ /^-+$/ || stage == "intake") next
      kind="todo"
      if (st ~ /^done/) kind="done"; else if (st ~ /^skipped/) kind="skip"
      else if (st ~ /^(in-progress|running|active|current)/) kind="now"
      else if (st ~ /^(blocked|on-hold|failed|waiting)/) kind="stop"
      doing=""
      if (kind == "now" || kind == "stop") {
        p=now; sub(/ .*/, "", p)
        if (now != "" && index("/" owner "/", "/" p "/")) { doing=now; sub(/^[^ ]+ /, "", doing) }
        else { doing=trim($5); sub(/^[A-Za-z-]+ *[—-]? */, "", doing) }
      }
      print kind "\t" stage "\t" owner "\t" doing
    }' "$d/STATUS.md" 2>/dev/null)
  line
  envs="$(awk '/^(Dev|QA|Staging|Production):/ { k=tolower($1); sub(/:$/,"",k); v[k]=substr($2,1,7) }
    END { printf "dev %s  qa %s  staging %s  prod %s", (v["dev"]?v["dev"]:"-"), (v["qa"]?v["qa"]:"-"), (v["staging"]?v["staging"]:"-"), (v["production"]?v["production"]:"-") }' "$d/releases.md" 2>/dev/null)"
  open="$(awk -F'|' '{ k=$3; s=$6; gsub(/ /,"",k); gsub(/ /,"",s) } k=="defect" && s ~ /^(open|in-progress|reopened|fixed)$/ { n++ } END { print n+0 }' "$d/tickets.md" 2>/dev/null)"
  printf ' %s%s%s    %sopen defects: %s%s\n' "$D" "${envs:-dev -  qa -  staging -  prod -}" "$N" "$C" "${open:-0}" "$N"
  if [ -f "$act_dir/$t.log" ]; then
    local first=1
    while IFS=$'\t' read -r h _ txt; do
      [ "$first" = 1 ] && { printf ' %slast handoffs%s\n' "$B" "$N"; first=0; }
      printf '   %s%s%s  %.72s\n' "$D" "$h" "$N" "$txt"
    done < <(awk -F'\t' '$2=="handoff"' "$act_dir/$t.log" | tail -n 4)
  fi
}

all() { # one line per ticket in flight: the first stage not done or skipped
  local d
  for d in docs/pipeline/*/STATUS.md; do
    case "$d" in docs/pipeline/_*) continue;; esac
    [ -f "$d" ] || continue
    awk -F'|' -v t="$(basename "$(dirname "$d")")" '
      function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
      /^\|/ && NR > 2 { st=trim($5); s=trim($3); o=trim($4); sub(/ *\(.*$/, "", o)
        if (s == "" || s == "Stage" || s ~ /^-+$/ || s == "intake") next
        if (tolower(st) !~ /^(done|skipped)/) { printf "%-10s %-11s %-22.22s %.30s\n", t, s, o, st; exit } }' "$d"
  done
}

case "${1:-}" in
  ""|-h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  --all) all; exit 0;;
esac
ticket="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; shift
bash "$here/ticket-id.sh" "$ticket" >/dev/null 2>&1 || { echo "board: '$ticket' is not a ticket id for this project" >&2; exit 1; }
case "${1:-}" in
  "") draw "$ticket";;
  --watch)
    secs="${2:-3}"
    trap 'printf "\n"; exit 0' INT TERM
    while :; do out="$(draw "$ticket" 2>&1)"; printf '\e[H\e[2J%s\n' "$out"; sleep "$secs"; done;;
  --pane)
    cmd="bash scripts/pipeline/board.sh $ticket --watch"
    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
      tmux split-window -h -l 70 -c "$root" "$cmd" && echo "board: watching $ticket in a tmux side pane"
    else
      echo "board: to watch $ticket live, run this in a second terminal (or start /ship inside tmux for a side pane):"
      echo "  cd \"$root\" && $cmd"
    fi;;
  now) [ -n "${3:-}" ] || { echo "usage: board.sh <TICKET> now <persona> <doing>" >&2; exit 1; }
    p="$2"; shift 2; record "$ticket" now "$p" "$@";;
  handoff) [ -n "${4:-}" ] || { echo "usage: board.sh <TICKET> handoff <from> <to> <reason>" >&2; exit 1; }
    f="$2"; to="$3"; shift 3; record "$ticket" handoff "$f $ARROW $to:" "$@"; record "$ticket" now "$to" "picking it up";;
  *) echo "usage: board.sh <TICKET> [--watch [SECONDS] | --pane | now <persona> <doing> | handoff <from> <to> <reason>] | board.sh --all" >&2; exit 1;;
esac
