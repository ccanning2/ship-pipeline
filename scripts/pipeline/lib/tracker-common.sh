# Shared by every tracker adapter (sourced, never run). /pipeline-init installs ONE adapter as scripts/pipeline/tracker.sh,
# chosen by TRACKER (adapters/tracker-<name>.sh); the adapter sets $tracker and $pfx, defines <pfx>_<verb> functions,
# then calls tracker_main "$@". The adapters, all through CLIs rather than MCP connectors:
#   jira    Atlassian CLI (acli) for work items; Jira REST (same API token) for fields, statuses and field values
#   linear  Linear GraphQL API with a personal API key (Linear has no official CLI; the community one cannot manage
#           labels or workflow states)
#   github  gh (GitHub Issues of this repository; ticket KEY-12 is issue #12)
#   gitlab  glab (GitLab issues of this project; ticket KEY-12 is issue #12)
#   connector  no CLI: every verb exits 3 and the caller uses the tracker's MCP connector tools instead
# TRACKER, TRACKER_URL and TRACKER_TEAM_KEY come from scripts/pipeline/pipeline.env. Credentials never live in the
# repository: gh and glab keep their own; the Jira and Linear tokens are in ~/.config/ship-pipeline/<tracker>.env,
# written by `connect.sh login` (or JIRA_EMAIL/JIRA_API_TOKEN, LINEAR_API_KEY in the environment).
#
# Usage: tracker.sh <verb> [args]      (bodies: --body 'text' | --body-file FILE | --body-file - for stdin)
#   check                              the tracker answers and the team/project exists
#   view <ID>                          title, state, Stage, Owner, labels, url, description, children, latest comments
#   children <ID>                      one line per child: ID | kind | state | title
#   create <PARENT> <kind> <title> <body>   a child ticket with its kind label; prints the new id
#   comment <ID> <body>
#   describe <ID> <body>               replace the description (product owner and business analyst only)
#   set <ID> [stage=<v>] [owner=<v>]   set the parent's Stage / Owner (one value per group; the old one is removed)
#   handoff <ID> <stage> <owner> <body>   set Stage + Owner and post the handoff comment, in one call
#   state <ID> <open|reopened|in-progress|fixed|verified|done|wontfix>
#   setup [--check]                    create every label, field and status tracker-schema.txt names (or, with
#                                      --check, only report what is missing); writes scripts/pipeline/tracker.map
# Exit codes: 0 ok, 1 error, 2 setup --check found missing items, 3 TRACKER=connector (use the MCP connector).
# Test doubles: PIPELINE_GH_CMD, PIPELINE_GLAB_CMD, PIPELINE_ACLI_CMD, PIPELINE_CURL_CMD, PIPELINE_TRACKER_CONFIG.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # scripts/pipeline
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
key="$(printf '%s' "${TRACKER_TEAM_KEY:-}" | tr -cd 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
site="${TRACKER_URL:-}"; site="${site%/}"
schema="$here/tracker-schema.txt"; map="$here/tracker.map"
cfg="${PIPELINE_TRACKER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ship-pipeline}"
gh_cmd="${PIPELINE_GH_CMD:-gh}"; glab_cmd="${PIPELINE_GLAB_CMD:-glab}"; acli_cmd="${PIPELINE_ACLI_CMD:-acli}"; curl_cmd="${PIPELINE_CURL_CMD:-curl}"
die() { echo "tracker.sh: $*" >&2; exit 1; }
have() { command -v "${1%% *}" >/dev/null 2>&1; }
[ -f "$cfg/$tracker.env" ] && { set -a; # shellcheck disable=SC1090
  source "$cfg/$tracker.env"; set +a; }
[ "$tracker" = github ] || have jq || die "needs jq for $tracker (/pipeline-init installs it)"   # gh filters JSON itself

# ---- the schema (scripts/pipeline/tracker-schema.txt) ----
schema_rows() { grep -vE '^[[:space:]]*(#|$)' "$schema"; }
group_values() { schema_rows | awk -F'|' -v g="$1" '$1=="label-group" && $2==g {print $3}' | tr ',' '\n'; }
kinds() { schema_rows | awk -F'|' '$1=="labels" {print $3}' | tr ',' '\n'; }
states() { schema_rows | awk -F'|' '$1=="status" {print $2}'; }
map_get() { [ -f "$map" ] && awk -F'|' -v k="$1" '$1==k {v=$2} END {if (v!="") print v}' "$map"; }
# the tracker status a pipeline state maps to: tracker.map (written by setup), else the tracker's usual name
state_name() {
  local v; v="$(map_get "state:$1")"; [ -n "$v" ] && { echo "$v"; return; }
  case "$tracker:$1" in
    jira:open|jira:reopened) echo "To Do";; jira:in-progress) echo "In Progress";; jira:fixed) echo "In Review";;
    jira:verified|jira:done) echo "Done";; jira:wontfix) echo "Won't Do";;
    *) schema_rows | awk -F'|' -v s="$1" '$1=="status" && $2==s {print $3}';;
  esac
}
valid_in() { # <value> <list...>
  local v="$1"; shift; printf '%s\n' "$@" | grep -qxF "$v"
}
num_of() { printf '%s' "$1" | sed -E 's/^[A-Za-z0-9]+-//'; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# ---- bodies ----
body=""
read_body() { # sets $body from --body / --body-file in "$@"
  body=""
  while [ $# -gt 0 ]; do case "$1" in
    --body) body="${2:-}"; shift 2;;
    --body-file) if [ "${2:-}" = - ]; then body="$(cat)"; else [ -f "${2:-}" ] || die "no such file: ${2:-}"; body="$(cat "$2")"; fi; shift 2;;
    *) shift;; esac; done
}

# ---- shared setup helpers ----
nmissing=0
report_missing() { # <noun> <items...>: prints them; returns 1 when nothing is missing or only checking
  shift; nmissing=$#; if [ $# -eq 0 ]; then echo "PASS  tracker: every label, field and status the pipeline needs exists"; return 1; fi
  local m; for m in "$@"; do echo "MISSING $m"; done
  [ "$check_only" = 1 ] && return 1
  return 0
}
jira_map_extra=""
write_map() { # project-owned record of how the pipeline's names map onto this tracker; kept when it exists
  local t="$1" s fid
  [ "$check_only" = 1 ] && return 0
  {
    echo "# How the pipeline's states and label groups map onto this tracker ($t). Written by tracker.sh setup; edit to remap."
    for s in $(states); do echo "state:$s|$(state_name "$s")"; done
    if [ "$t" = jira ]; then
      for g in Stage Owner; do fid="$(jira_rest GET field | jq -r --arg g "$g" '[.[] | select(.custom and .name==$g)][0].id // empty')"; [ -n "$fid" ] && echo "jira:field:$g|$fid"; done
      printf '%s\n' "$jira_map_extra"
    fi
  } | awk -F'|' 'NF { k[$1]=$0; if (!($1 in o)) { o[$1]=++n } } END { for (x in o) line[o[x]]=k[x]; for (i=1;i<=n;i++) print line[i] }' > "$map.tmp"
  mv "$map.tmp" "$map"; echo "WROTE scripts/pipeline/tracker.map"
}

# ================================================================ dispatch (called by the adapter) ====
# credentials are checked once, here: a die inside $(...) only ends that subshell, so a missing key found deep in a
# call would be followed by a second, misleading error
case "$tracker" in
  linear) [ -n "${LINEAR_API_KEY:-}" ] || die "no Linear API key: the owner runs bash scripts/pipeline/connect.sh login once";;
  jira) [ -n "${JIRA_API_TOKEN:-}" ] || die "no Jira API token: the owner runs bash scripts/pipeline/connect.sh login once"
        [ -n "$site" ] || die "TRACKER_URL (the Jira site) is not set in pipeline.env";;
esac
tracker_main() {
check_only=0
verb="${1:-}"; [ $# -gt 0 ] && shift
need_id() { [ -n "${1:-}" ] || die "usage: tracker.sh $verb <ID> ..."; bash "$here/ticket-id.sh" "$1" >/dev/null || die "'$1' is not a $key ticket id"; }
case "$verb" in
  check) "${pfx}_check";;
  view) need_id "${1:-}"; "${pfx}_view" "$1";;
  children) need_id "${1:-}"; "${pfx}_children" "$1";;
  create)
    need_id "${1:-}"; [ -n "${3:-}" ] || die "usage: tracker.sh create <PARENT> <kind> <title> --body ...|--body-file F"
    valid_in "$2" $(kinds) || die "kind must be one of: $(kinds | tr '\n' ' ')"
    p="$1"; k="$2"; t="$3"; shift 3; read_body "$@"; "${pfx}_create" "$p" "$k" "$t";;
  comment|describe)
    need_id "${1:-}"; id="$1"; shift; read_body "$@"; [ -n "$body" ] || die "a --body or --body-file is required"; "${pfx}_$verb" "$id";;
  set)
    need_id "${1:-}"; id="$1"; shift
    for a in "$@"; do
      case "$a" in stage=*) g=Stage; v="${a#stage=}";; owner=*) g=Owner; v="${a#owner=}";; *) die "set takes stage=<v> owner=<v>";; esac
      valid_in "$v" $(group_values $g) || die "$g must be one of: $(group_values $g | tr '\n' ' ')"
      case "$pfx" in gh) gh_set_group "$id" "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" "$v";; *) "${pfx}_set_group" "$id" "$g" "$v";; esac
    done;;
  handoff)
    need_id "${1:-}"; [ -n "${3:-}" ] || die "usage: tracker.sh handoff <ID> <stage> <owner> --body ...|--body-file F"
    id="$1"; st="$2"; ow="$3"; shift 3; read_body "$@"; [ -n "$body" ] || die "the handoff comment (--body) is required"
    tracker_main set "$id" "stage=$st" "owner=$ow" || exit 1
    "${pfx}_comment" "$id" && echo "handoff: $id -> Stage $st, Owner $ow";;
  state)
    need_id "${1:-}"; valid_in "${2:-}" $(states) || die "state must be one of: $(states | tr '\n' ' ')"; "${pfx}_state" "$1" "$2";;
  setup) [ "${1:-}" = --check ] && check_only=1; "${pfx}_setup"; if [ "$check_only" = 1 ] && [ "$nmissing" -gt 0 ]; then exit 2; fi;;
  *) die "usage: tracker.sh <check|view|children|create|comment|describe|set|handoff|state|setup> ... (see the header)";;
esac
}
