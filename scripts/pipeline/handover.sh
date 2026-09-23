#!/usr/bin/env bash
# Record the work a team upstream of this project's start level already did, so /ship can pick a ticket up at
# that level and every gate still reads the same records. Run by /ship at intake; changes files, never commits.
# Usage: handover.sh <TICKET> [--level analysis|engineering|devops|qa] [--type T] [--user-facing yes|no]
#                    [--eng ID,ID...] [--sha SHA]
#   --level       default: PIPELINE_START_LEVEL in pipeline.env, else analysis
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
level=""; type=feature; uf=yes; eng=""; sha=""
while [ $# -gt 0 ]; do case "$1" in
  --level) level="${2:-}"; shift 2;; --type) type="${2:-}"; shift 2;; --user-facing) uf="${2:-}"; shift 2;;
  --eng) eng="${2:-}"; shift 2;; --sha) sha="${2:-}"; shift 2;;
  *) echo "handover: unknown argument $1" >&2; exit 1;; esac; done
root="$(git rev-parse --show-toplevel)"; cd "$root"
# shellcheck disable=SC1091
source scripts/pipeline/pipeline.env
[ -n "$level" ] || level="$(printf '%s' "${PIPELINE_START_LEVEL:-analysis}" | tr '[:upper:]' '[:lower:]')"
case "$level" in analysis|engineering|devops|qa) ;; *) echo "handover: level must be analysis, engineering, devops or qa (got '$level')" >&2; exit 1;; esac
[ "$(bash scripts/pipeline/ticket-id.sh "$ticket" 2>/dev/null)" = "$ticket" ] || { echo "handover: '$ticket' is not a ticket id for this project" >&2; exit 1; }
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
