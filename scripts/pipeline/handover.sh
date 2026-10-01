#!/usr/bin/env bash
# Record work done outside the selected teams, so every gate still reads the same records. Changes files, never
# commits. Two uses:
#   upstream  at intake, the work before the ticket's arrival point (another team did it):
#             handover.sh <TICKET> [--level analysis|engineering|devops|qa] [--type T] [--user-facing yes|no]
#                         [--eng ID,ID...] [--sha SHA]
#   owner     during a run, a stage whose team is not selected, done by the owner once they say it is done:
#             handover.sh <TICKET> --by-owner build|qa|signoff [--who NAME]
#               build    the eng rows are done and impl-notes.md is ready-for-dev (the code is on this branch)
#               qa       qa-report.md passes the build on qa (releases.md QA)
#               signoff  signoff.md approves the build on staging (releases.md Staging)
#   --level       default: scripts/pipeline/teams.sh <TICKET> --entry (the first selected team)
#   analysis      nothing to hand over: the product owner and business analyst run
#   engineering   the ticket arrives analysed and ready for dev: product.md and requirements.md are recorded as
#                 approved from the ticket, and the eng rows (--eng, default the ticket itself) go into tickets.md
#   devops        also built: the eng rows are done and impl-notes.md is ready-for-dev (the code is on this branch)
#   qa            also on qa: releases.md Dev/QA and a passing dev-check.md record --sha (default: the staging
#                 branch on the remote), which must already be on the base branch
#   --type        feature | bugfix | security | chore (default feature)   --user-facing  yes | no (default yes)
# A record that already exists is never overwritten, so a resumed /ship keeps what is there.
set -euo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"; [ $# -gt 0 ] && shift
level=""; type=feature; uf=yes; eng=""; sha=""; by=""; who="the owner"
while [ $# -gt 0 ]; do case "$1" in
  --level) level="${2:-}"; shift 2;; --type) type="${2:-}"; shift 2;; --user-facing) uf="${2:-}"; shift 2;;
  --eng) eng="${2:-}"; shift 2;; --sha) sha="${2:-}"; shift 2;;
  --by-owner) by="${2:-}"; shift 2;; --who) who="${2:-}"; shift 2;;
  *) echo "handover: unknown argument $1" >&2; exit 1;; esac; done
root="$(git rev-parse --show-toplevel)"; cd "$root"
# shellcheck disable=SC1091
source scripts/pipeline/pipeline.env
[ "$(bash scripts/pipeline/ticket-id.sh "$ticket" 2>/dev/null)" = "$ticket" ] || { echo "handover: '$ticket' is not a ticket id for this project" >&2; exit 1; }
if [ -n "$by" ]; then # ---- a stage the owner did, mid-run ----
  d="docs/pipeline/$ticket"; tpl=docs/pipeline/_templates; stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -f "$d/tickets.md" ] || { echo "handover: $d/tickets.md is missing (run /ship $ticket from intake)" >&2; exit 1; }
  env_sha() { awk -v k="$1:" '$1==k { print $2; exit }' "$d/releases.md" 2>/dev/null; }
  note="Done by $who, not by a pipeline persona: the $by team is not selected for this ticket (scripts/pipeline/teams.sh)."
  case "$by" in
    build)
      [ -e "$d/impl-notes.md" ] && grep -qiE '^Status: *ready-for-dev' "$d/impl-notes.md" && { echo "handover: kept $d/impl-notes.md"; exit 0; }
      printf '# %s — Implementation notes\n\nStatus: ready-for-dev\n\n%s The code is on branch %s at %s.\n' \
        "$ticket" "$note" "$(git rev-parse --abbrev-ref HEAD)" "$(git rev-parse --short HEAD)" > "$d/impl-notes.md"
      # the owner's build covers the open eng rows
      awk -F'|' 'BEGIN { OFS="|" } { k=$3; s=$6; gsub(/ /,"",k); gsub(/ /,"",s) }
        k=="eng" && s!="done" && s!="wontfix" { $6=" done " } { print }' "$d/tickets.md" > "$d/tickets.md.tmp" && mv "$d/tickets.md.tmp" "$d/tickets.md"
      echo "handover: $ticket build by $who (impl-notes.md ready-for-dev, eng rows done)";;
    qa|signoff)
      if [ "$by" = qa ]; then f=qa-report.md; lab=QA; env=qa; head="QA report"; res="Result: pass"
      else f=signoff.md; lab=Staging; env=staging; head="Staging sign-off"; res="Decision: approved"; fi
      s="$(env_sha "$lab")"; [ -n "$s" ] || { echo "handover: releases.md has no $lab line: promote the build to $env first" >&2; exit 1; }
      if [ -e "$d/$f" ] && grep -qiE "^(Result: *pass|Decision: *approved)" "$d/$f" && grep -qiE "^Commit: *$s" "$d/$f"; then echo "handover: kept $d/$f"; exit 0; fi
      printf '# %s — %s\n\n%s\nEnvironment: %s\nCommit: %s\nSigned: %s\n\n%s\n' "$ticket" "$head" "$res" "$env" "$s" "$stamp" "$note" > "$d/$f"
      echo "handover: $ticket $by by $who ($f records $s)";;
    *) echo "handover: --by-owner takes build, qa or signoff (got '$by')" >&2; exit 1;;
  esac
  exit 0
fi
[ -n "$level" ] || level="$(bash scripts/pipeline/teams.sh "$ticket" --entry)" || exit 1
level="$(printf '%s' "$level" | tr '[:upper:]' '[:lower:]')"
case "$level" in analysis|engineering|devops|qa) ;; *) echo "handover: level must be analysis, engineering, devops or qa (got '$level')" >&2; exit 1;; esac
case "$type" in feature|bugfix|security|chore) ;; *) echo "handover: --type must be feature, bugfix, security or chore" >&2; exit 1;; esac
case "$uf" in yes|no) ;; *) echo "handover: --user-facing must be yes or no" >&2; exit 1;; esac
[ "$level" = analysis ] && { echo "handover: level analysis, nothing to hand over"; exit 0; }
d="docs/pipeline/$ticket"; tpl=docs/pipeline/_templates
[ -f "$d/brief.md" ] || { echo "handover: run intake.sh first ($d/brief.md is missing)" >&2; exit 1; }
case "$level" in
  engineering) upstream="the analysis was";; devops) upstream="the analysis and the build were";;
  qa) upstream="the analysis, the build and the dev and qa deploys were";; esac
note="Handed over at the $level level: $upstream done upstream of this project; the source is the tracker ticket (brief.md)."
done_list=()
write_once() { # <file> <content>: never overwrites
  if [ -e "$1" ]; then echo "handover: kept $1"; else printf '%s\n' "$2" > "$1"; done_list+=("$1"); fi
}
write_once "$d/product.md" "# $ticket — Product definition

Status: approved
Type: $type
User-facing: $uf

$note
"
write_once "$d/requirements.md" "# $ticket — Requirements (engineer-ready)

Status: approved
Traces to: brief.md

$note The requirement and its acceptance criteria are the ticket's description, in brief.md.
"
[ -f "$d/tickets.md" ] || cp "$tpl/tickets.md" "$d/tickets.md"
state=open; [ "$level" = engineering ] || state=done
for id in $(printf '%s' "${eng:-$ticket}" | tr ',' ' ' | tr '[:lower:]' '[:upper:]'); do
  if grep -qE "^\| $id \|" "$d/tickets.md"; then echo "handover: kept the $id row"
  else printf '| %s | eng | - | - | %s | engineer | handed over at the %s level |\n' "$id" "$state" "$level" >> "$d/tickets.md"; done_list+=("$d/tickets.md: $id"); fi
done
if [ "$level" = devops ] || [ "$level" = qa ]; then
  write_once "$d/impl-notes.md" "# $ticket — Implementation notes

Status: ready-for-dev

$note The code is on branch $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD).
"
fi
if [ "$level" = qa ]; then
  remote="$(bash scripts/pipeline/base-ref.sh --remote)"; stg="$(bash scripts/pipeline/base-ref.sh --staging)"
  [ -n "$sha" ] || sha="$(git ls-remote --heads "$remote" "refs/heads/$stg" 2>/dev/null | awk '{print $1}' || true)"
  [ -n "$sha" ] || sha="$(git rev-parse -q --verify "refs/remotes/$remote/$stg" 2>/dev/null || true)"
  [ -n "$sha" ] || { echo "handover: no --sha and no $remote/$stg to take the build on qa from" >&2; exit 1; }
  sha="$(git rev-parse "$sha^{commit}")" || { echo "handover: $sha is not a commit here (git fetch first)" >&2; exit 1; }
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -f "$d/releases.md" ] || cp "$tpl/releases.md" "$d/releases.md"
  for lab in Dev QA; do
    if grep -qE "^$lab:" "$d/releases.md"; then echo "handover: kept releases.md $lab"
    else printf '%s: %s %s\n' "$lab" "$sha" "$stamp" >> "$d/releases.md"; done_list+=("$d/releases.md: $lab $sha"); fi
  done
  write_once "$d/dev-check.md" "# $ticket — Dev check

Result: pass
Environment: dev
Commit: $sha

$note The build was already on qa.
"
fi
echo "handover: $ticket at the $level level"
for x in ${done_list[@]+"${done_list[@]}"}; do printf '  wrote %s\n' "$x"; done
