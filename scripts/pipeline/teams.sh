#!/usr/bin/env bash
# Which teams run a ticket through /ship, and what happens to the stages of the teams that don't.
# Usage: teams.sh [TICKET]                 the teams, comma-separated in pipeline order
#        teams.sh [TICKET] --has <team>    exit 0 when that team is selected
#        teams.sh [TICKET] --entry         where a ticket arrives: analysis | engineering | devops | qa (the
#                                          handover.sh level; the work before it was done upstream)
#        teams.sh [TICKET] --stages        one line per stage: <stage> <TAB> <who> <TAB> <run|upstream|owner|off>
#        teams.sh --normalize <list>       check and complete a selection: prints it in pipeline order, and on
#                                          stderr one line for each team it had to add
# The teams, in order (a selection is any set of them):
#   analysis     product-owner + business-analyst (always together: the BA works from the PO's definition)
#   engineering  senior-engineer
#   devops       devops: every merge, promotion and tag
#   qa           qa-tester (needs devops: the build must be promoted to qa)
#   signoff      app-specialist (needs devops: the build must be on staging)
# Names are forgiving: po, ba, product-owner, business-analyst -> analysis; engineer, senior-engineer ->
# engineering; qa-tester, testing -> qa; app-specialist, sign-off -> signoff; all -> every team.
# A stage whose team is not selected is
#   upstream  when it comes before the first selected team: another team did it, handover.sh records it at intake
#   owner     after that, when devops is selected: the owner does it, /ship waits and records it (handover.sh --by)
#   off       after that, when devops is not: the pipeline ends there and hands the ticket to the owner
# Go-live is always the owner's, and runs only when devops does.
# The selection: the ticket's STATUS.md "Teams:" line (a per-ticket choice from /ship), else PIPELINE_TEAMS in
# pipeline.env, else PIPELINE_START_LEVEL (installs before 3.1.0): that level and every team after it.
set -uo pipefail
all_teams="analysis engineering devops qa signoff"
die() { echo "teams: $*" >&2; exit 1; }

normalize() { # <list> -> sets $out (comma list in order), $added (notes); fails on an unknown or empty list
  local raw t seen=" " w
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ',;+&/' '     ')"
  for w in $raw; do
    case "$w" in
      and|the|team|teams|only) continue;;
      all|full|everyone) t="$all_teams";;
      analysis|po|ba|product|product-owner|business-analyst|product-owner+business-analyst) t=analysis;;
      engineering|engineer|senior-engineer|eng|build|developer) t=engineering;;
      devops|ops|promotion|promote) t=devops;;
      qa|qa-tester|tester|testing|quality|quality-assurance) t=qa;;
      signoff|sign-off|app-specialist|specialist|release) t=signoff;;
      *) die "unknown team '$w' (teams: analysis, engineering, devops, qa, signoff)";;
    esac
    for w in $t; do seen="$seen$w "; done
  done
  [ "$seen" != " " ] || die "no team selected (teams: analysis, engineering, devops, qa, signoff)"
  added=""
  case "$seen" in *" devops "*) ;; *)
    case "$seen" in *" qa "*|*" signoff "*) seen="${seen}devops "; added="devops (qa and signoff need devops to promote the build)";; esac;;
  esac
  out=""; for t in $all_teams; do case "$seen" in *" $t "*) out="${out:+$out,}$t";; esac; done
}

from_level() { # <start level> -> the teams from that level on (devops always ran the later promotions)
  case "$1" in
    ""|analysis) echo "analysis,engineering,devops,qa,signoff";; engineering) echo "engineering,devops,qa,signoff";;
    devops|qa) echo "devops,qa,signoff";; *) die "PIPELINE_START_LEVEL '$1' is not analysis, engineering, devops or qa";;
  esac
}

if [ "${1:-}" = --normalize ]; then
  normalize "${2:-}"; [ -z "$added" ] || echo "teams: added $added" >&2; echo "$out"; exit 0
fi
case "${1:-}" in
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  ""|--*) ticket="";; *) ticket="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; shift;;
esac
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
# shellcheck disable=SC1091
[ -f "$root/scripts/pipeline/pipeline.env" ] && source "$root/scripts/pipeline/pipeline.env"
level="$(printf '%s' "${PIPELINE_START_LEVEL:-}" | tr '[:upper:]' '[:lower:]')"
sel=""; entry=""
if [ -n "$ticket" ] && [ -f "$root/docs/pipeline/$ticket/STATUS.md" ]; then
  sel="$(awk -F': *' '/^Teams:/ { sub(/^Teams: */, ""); sub(/ *\(.*$/, ""); print; exit }' "$root/docs/pipeline/$ticket/STATUS.md")"
  entry="$(awk '/^Arrives at:/ { print tolower($3); exit }' "$root/docs/pipeline/$ticket/STATUS.md")"
  case "$sel" in ""|project|"<"*) sel="";; esac
fi
if [ -z "$sel" ]; then
  if [ -n "${PIPELINE_TEAMS:-}" ]; then sel="$PIPELINE_TEAMS"
  else sel="$(from_level "$level")" || exit 1; [ -n "$entry" ] || { [ "$level" = qa ] && entry=qa; }; fi
fi
normalize "$sel"; sel="$out"
case ",$sel," in *,devops,*) ops=1;; *) ops=0;; esac
case "$entry" in ""|"<"*) entry="${sel%%,*}";; esac
case "$entry" in analysis|engineering|devops) ;; qa) [ "$ops" = 1 ] || die "a ticket can arrive on qa only when devops is selected";;
  *) die "Arrives at '$entry' is not analysis, engineering, devops or qa";; esac

case "${1:-}" in
  "") echo "$sel";;
  --has) [ -n "${2:-}" ] || die "usage: teams.sh [TICKET] --has <team>"; normalize "$2"
    case ",$sel," in *",$out,"*) exit 0;; *) exit 1;; esac;;
  --entry) echo "$entry";;
  --stages)
    # stage, its team, who runs it; the position of the arrival point decides what comes before it
    before=1
    while read -r st team who; do
      [ "$team" = "$entry" ] && before=0
      if [ "$team" = owner ]; then mode=$([ "$ops" = 1 ] && echo run || echo off)
      else case ",$sel," in
        *",$team,"*) mode=run; [ "$before" = 1 ] && mode=upstream;;
        *) if [ "$before" = 1 ]; then mode=upstream; elif [ "$ops" = 1 ]; then mode=owner; else mode=off; fi;;
      esac; fi
      printf '%s\t%s\t%s\n' "$st" "$who" "$mode"
    done <<'EOF'
product analysis product-owner
analysis analysis business-analyst
build engineering senior-engineer
dev devops devops
qa qa qa-tester
staging signoff app-specialist
go-live owner owner
production devops devops
EOF
    ;;
  *) die "usage: teams.sh [TICKET] [--has <team> | --entry | --stages] | teams.sh --normalize <list>";;
esac
