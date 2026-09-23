#!/usr/bin/env bash
# The tracker, behind one interface, driven through CLIs rather than MCP connectors:
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
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
tracker="$(printf '%s' "${TRACKER:-linear}" | tr '[:upper:]' '[:lower:]')"
key="$(printf '%s' "${TRACKER_TEAM_KEY:-}" | tr -cd 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
site="${TRACKER_URL:-}"; site="${site%/}"
schema="$here/tracker-schema.txt"; map="$here/tracker.map"
cfg="${PIPELINE_TRACKER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ship-pipeline}"
gh_cmd="${PIPELINE_GH_CMD:-gh}"; glab_cmd="${PIPELINE_GLAB_CMD:-glab}"; acli_cmd="${PIPELINE_ACLI_CMD:-acli}"; curl_cmd="${PIPELINE_CURL_CMD:-curl}"
die() { echo "tracker.sh: $*" >&2; exit 1; }
have() { command -v "${1%% *}" >/dev/null 2>&1; }
[ "$tracker" = connector ] && { echo "tracker.sh: TRACKER=connector: use the tracker's MCP connector tools for this step" >&2; exit 3; }
case "$tracker" in jira|linear|github|gitlab) ;; *) die "unknown TRACKER '$tracker' (jira | linear | github | gitlab | connector)";; esac
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

# ================================================================ GitHub Issues (gh) ====
# Stage/Owner are labels "stage:<v>" / "owner:<v>", kinds are plain labels, and states are open/closed plus a
# "state:<v>" label for in-progress and fixed. Children are GitHub sub-issues.
gh_repo() { $gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || die "gh cannot see this repository"; }
gh_check() { $gh_cmd auth status >/dev/null 2>&1 || die "gh is not signed in (bash scripts/pipeline/connect.sh login)"; gh_repo >/dev/null; echo "tracker: GitHub Issues of $(gh_repo)"; }
gh_view() {
  local n; n="$(num_of "$1")"
  $gh_cmd issue view "$n" --json number,title,body,state,labels,url,comments -q '
    "ID: '"$1"'\nTitle: \(.title)\nState: \(.state)\n" +
    "Stage: \([.labels[].name | select(startswith("stage:")) | ltrimstr("stage:")] | join(","))\n" +
    "Owner: \([.labels[].name | select(startswith("owner:")) | ltrimstr("owner:")] | join(","))\n" +
    "Labels: \([.labels[].name] | join(", "))\nURL: \(.url)\n--- description\n\(.body)\n--- comments (latest 10)\n" +
    ([.comments[-10:][] | "[\(.createdAt)] \(.author.login): \(.body)"] | join("\n"))' || die "no issue #$n"
  echo "--- children"; gh_children "$1"
}
gh_children() {
  $gh_cmd api "repos/$(gh_repo)/issues/$(num_of "$1")/sub_issues" -q '.[] | "'"$key"'-\(.number) | \([.labels[].name | select(test("^(stage|owner|state):") | not)] | join(",")) | \(.state)\([.labels[].name | select(startswith("state:")) | " " + ltrimstr("state:")] | join("")) | \(.title)"' 2>/dev/null || true
}
gh_create() { # parent kind title
  local url n id; url="$($gh_cmd issue create --title "$3" --body "$body" --label "$2")" || die "could not create the issue"
  n="${url##*/}"
  id="$($gh_cmd api "repos/$(gh_repo)/issues/$n" -q .id)"
  $gh_cmd api -X POST "repos/$(gh_repo)/issues/$(num_of "$1")/sub_issues" -F sub_issue_id="$id" >/dev/null || echo "tracker.sh: warning: #$n was not linked as a sub-issue of $1" >&2
  echo "$key-$n"
}
gh_comment() { $gh_cmd issue comment "$(num_of "$1")" --body "$body" >/dev/null; }
gh_describe() { $gh_cmd issue edit "$(num_of "$1")" --body "$body" >/dev/null; }
gh_set_group() { # id group value
  local n cur rm=""; n="$(num_of "$1")"
  cur="$($gh_cmd issue view "$n" --json labels -q '[.labels[].name | select(startswith("'"$2"':"))] | join(",")')"
  for l in $(printf '%s' "$cur" | tr ',' ' '); do [ "$l" = "$2:$3" ] || rm="${rm:+$rm,}$l"; done
  $gh_cmd issue edit "$n" --add-label "$2:$3" ${rm:+--remove-label "$rm"} >/dev/null
}
gh_state() { # id state
  local n; n="$(num_of "$1")"
  case "$2" in
    verified|done) $gh_cmd issue close "$n" --reason completed >/dev/null 2>&1 || true;;
    wontfix) $gh_cmd issue close "$n" --reason "not planned" >/dev/null 2>&1 || true;;
    *) $gh_cmd issue reopen "$n" >/dev/null 2>&1 || true;;
  esac
  local rm; rm="$($gh_cmd issue view "$n" --json labels -q '[.labels[].name | select(startswith("state:"))] | join(",")')"
  case "$2" in in-progress|fixed) $gh_cmd issue edit "$n" --add-label "state:$2" ${rm:+--remove-label "$rm"} >/dev/null;;
    *) [ -z "$rm" ] || $gh_cmd issue edit "$n" --remove-label "$rm" >/dev/null;; esac
}
gh_setup() { # check-only
  local have_labels want=() missing=() l
  have_labels="$($gh_cmd label list --limit 500 --json name -q '.[].name' 2>/dev/null)"
  for l in $(group_values Stage); do want+=("stage:$l|0e8a16"); done
  for l in $(group_values Owner); do want+=("owner:$l|1d76db"); done
  for l in $(kinds); do want+=("$l|5319e7"); done
  want+=("state:in-progress|fbca04" "state:fixed|c2e0c6")
  for l in "${want[@]}"; do printf '%s\n' "$have_labels" | grep -qxF "${l%%|*}" || missing+=("$l"); done
  report_missing "label" "${missing[@]+"${missing[@]}"}" || return 0
  for l in "${missing[@]}"; do $gh_cmd label create "${l%%|*}" --color "${l##*|}" --force >/dev/null && echo "CREATED label ${l%%|*}"; done
  write_map github
}

# ================================================================ GitLab issues (glab) ====
# Stage/Owner are scoped labels "Stage::<v>" / "Owner::<v>" (mutually exclusive on Premium; the adapter removes the old
# one on every tier), kinds are plain labels, states are opened/closed plus "state::<v>". Children are linked issues.
gl() { $glab_cmd api "$@"; }
gl_check() { $glab_cmd auth status >/dev/null 2>&1 || die "glab is not signed in (bash scripts/pipeline/connect.sh login)"; gl "projects/:id" >/dev/null || die "glab cannot see this project"; echo "tracker: GitLab issues of $(gl projects/:id | jq -r .path_with_namespace)"; }
gl_view() {
  local n j; n="$(num_of "$1")"; j="$(gl "projects/:id/issues/$n")" || die "no issue #$n"
  printf '%s' "$j" | jq -r '"ID: '"$1"'\nTitle: \(.title)\nState: \(.state)\n" +
    "Stage: \([.labels[] | select(startswith("Stage::")) | ltrimstr("Stage::")] | join(","))\n" +
    "Owner: \([.labels[] | select(startswith("Owner::")) | ltrimstr("Owner::")] | join(","))\n" +
    "Labels: \(.labels | join(", "))\nURL: \(.web_url)\n--- description\n\(.description // "")"'
  echo "--- comments (latest 10)"
  gl "projects/:id/issues/$n/notes?sort=desc&per_page=10" | jq -r 'reverse | .[] | select(.system|not) | "[\(.created_at)] \(.author.username): \(.body)"'
  echo "--- children"; gl_children "$1"
}
gl_children() {
  gl "projects/:id/issues/$(num_of "$1")/links" 2>/dev/null | jq -r '.[] | select(.description // "" | test("^Parent: '"$(upper "$1")"'\\b")) |
    "'"$key"'-\(.iid) | \([.labels[] | select(test("::") | not)] | join(",")) | \(.state)\([.labels[] | select(startswith("state::")) | " " + ltrimstr("state::")] | join("")) | \(.title)"' || true
}
gl_create() {
  local j n pid; pid="$(gl projects/:id | jq -r .id)"
  j="$(gl -X POST "projects/:id/issues" -f title="$3" -f description="Parent: $(upper "$1")

$body" -f labels="$2")" || die "could not create the issue"
  n="$(printf '%s' "$j" | jq -r .iid)"
  gl -X POST "projects/:id/issues/$(num_of "$1")/links" -f target_project_id="$pid" -f target_issue_iid="$n" >/dev/null || echo "tracker.sh: warning: #$n was not linked to $1" >&2
  echo "$key-$n"
}
gl_comment() { gl -X POST "projects/:id/issues/$(num_of "$1")/notes" -f body="$body" >/dev/null; }
gl_describe() { gl -X PUT "projects/:id/issues/$(num_of "$1")" -f description="$body" >/dev/null; }
gl_set_group() { # id Group value
  local n rm; n="$(num_of "$1")"
  rm="$(gl "projects/:id/issues/$n" | jq -r --arg p "$2::" --arg k "$2::$3" '[.labels[] | select(startswith($p) and . != $k)] | join(",")')"
  gl -X PUT "projects/:id/issues/$n" -f add_labels="$2::$3" ${rm:+-f remove_labels="$rm"} >/dev/null
}
gl_state() {
  local n rm ev=reopen; n="$(num_of "$1")"
  case "$2" in verified|done|wontfix) ev=close;; esac
  rm="$(gl "projects/:id/issues/$n" | jq -r '[.labels[] | select(startswith("state::"))] | join(",")')"
  case "$2" in
    in-progress|fixed) gl -X PUT "projects/:id/issues/$n" -f state_event=$ev -f add_labels="state::$2" ${rm:+-f remove_labels="$rm"} >/dev/null;;
    wontfix) gl -X PUT "projects/:id/issues/$n" -f state_event=$ev -f add_labels="state::wontfix" ${rm:+-f remove_labels="$rm"} >/dev/null;;
    *) gl -X PUT "projects/:id/issues/$n" -f state_event=$ev ${rm:+-f remove_labels="$rm"} >/dev/null;;
  esac
}
gl_setup() {
  local have_labels want=() missing=() l
  have_labels="$(gl "projects/:id/labels?per_page=100&include_ancestor_groups=true" --paginate | jq -r '.[].name')"
  for l in $(group_values Stage); do want+=("Stage::$l|#0e8a16"); done
  for l in $(group_values Owner); do want+=("Owner::$l|#1d76db"); done
  for l in $(kinds); do want+=("$l|#5319e7"); done
  want+=("state::in-progress|#fbca04" "state::fixed|#c2e0c6" "state::wontfix|#cccccc")
  for l in "${want[@]}"; do printf '%s\n' "$have_labels" | grep -qxF "${l%%|*}" || missing+=("$l"); done
  report_missing "label" "${missing[@]+"${missing[@]}"}" || return 0
  for l in "${missing[@]}"; do gl -X POST "projects/:id/labels" -f name="${l%%|*}" -f color="${l##*|}" >/dev/null && echo "CREATED label ${l%%|*}"; done
  write_map gitlab
}

# ================================================================ Linear (GraphQL) ====
# Stage/Owner are label groups (one child label per issue), kinds are plain labels, states are the team's workflow
# states. Children are sub-issues.
lin() { # <query> [jq --arg pairs...] -> data
  local q="$1"; shift
  [ -n "${LINEAR_API_KEY:-}" ] || die "no Linear API key (bash scripts/pipeline/connect.sh login)"
  local payload out; payload="$(jq -nc --arg q "$q" "$@" '{query: $q, variables: ($ARGS.named | del(.q))}')"
  out="$($curl_cmd -fsS https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" -H 'Content-Type: application/json' --data "$payload")" \
    || die "the Linear API did not answer"
  printf '%s' "$out" | jq -e '.errors | not' >/dev/null 2>&1 || die "Linear: $(printf '%s' "$out" | jq -r '.errors[0].message')"
  printf '%s' "$out" | jq -c .data
}
lin_team() { lin 'query($k:String!){teams(filter:{key:{eq:$k}}){nodes{id name states{nodes{id name type}}}}}' --arg k "$key" | jq -c '.teams.nodes[0] // empty'; }
lin_labels() { # all labels usable by the team (team + workspace)
  lin 'query{issueLabels(first:250){nodes{id name isGroup team{key} parent{id name}}}}' | jq -c --arg k "$key" '[.issueLabels.nodes[] | select(.team == null or .team.key == $k)]'
}
lin_check() { local t; t="$(lin_team)"; [ -n "$t" ] || die "Linear has no team with key $key"; echo "tracker: Linear team $(printf '%s' "$t" | jq -r .name) ($key)"; }
lin_issue() { lin 'query($id:String!){issue(id:$id){id identifier title description url state{name} labels{nodes{id name parent{name}}} children{nodes{identifier title state{name} labels{nodes{name parent{name}}}}} comments(last:10){nodes{body createdAt user{name}}}}}' --arg id "$(upper "$1")" | jq -c '.issue // empty'; }
lin_view() {
  local j; j="$(lin_issue "$1")"; [ -n "$j" ] || die "no Linear issue $1"
  printf '%s' "$j" | jq -r '"ID: \(.identifier)\nTitle: \(.title)\nState: \(.state.name)\n" +
    "Stage: \([.labels.nodes[] | select(.parent.name=="Stage") | .name] | join(","))\n" +
    "Owner: \([.labels.nodes[] | select(.parent.name=="Owner") | .name] | join(","))\n" +
    "Labels: \([.labels.nodes[].name] | join(", "))\nURL: \(.url)\n--- description\n\(.description // "")\n--- comments (latest 10)\n" +
    ([.comments.nodes[] | "[\(.createdAt)] \(.user.name // "?"): \(.body)"] | join("\n")) + "\n--- children\n" +
    ([.children.nodes[] | "\(.identifier) | \([.labels.nodes[] | select(.parent == null) | .name] | join(",")) | \(.state.name) | \(.title)"] | join("\n"))'
}
lin_children() { lin_issue "$1" | jq -r '.children.nodes[] | "\(.identifier) | \([.labels.nodes[] | select(.parent == null) | .name] | join(",")) | \(.state.name) | \(.title)"'; }
lin_label_id() { # name [group]
  lin_labels | jq -r --arg n "$1" --arg g "${2:-}" '[.[] | select(.name==$n and .isGroup==false and (if $g=="" then .parent==null else .parent.name==$g end))][0].id // empty'
}
lin_create() {
  local t pid lid j; t="$(lin_team | jq -r .id)"; pid="$(lin_issue "$1" | jq -r .id)"; lid="$(lin_label_id "$2")"
  [ -n "$pid" ] || die "no Linear issue $1"; [ -n "$lid" ] || die "Linear has no '$2' label (bash scripts/pipeline/tracker.sh setup)"
  j="$(lin 'mutation($t:String!,$p:String!,$ti:String!,$d:String!,$l:String!){issueCreate(input:{teamId:$t,parentId:$p,title:$ti,description:$d,labelIds:[$l]}){issue{identifier}}}' \
      --arg t "$t" --arg p "$pid" --arg ti "$3" --arg d "$body" --arg l "$lid")"
  printf '%s' "$j" | jq -r .issueCreate.issue.identifier
}
lin_comment() { local id; id="$(lin_issue "$1" | jq -r .id)"; [ -n "$id" ] || die "no Linear issue $1"
  lin 'mutation($i:String!,$b:String!){commentCreate(input:{issueId:$i,body:$b}){success}}' --arg i "$id" --arg b "$body" >/dev/null; }
lin_uuid() { local id; id="$(lin 'query($id:String!){issue(id:$id){id}}' --arg id "$(upper "$1")" | jq -r '.issue.id // empty')"; [ -n "$id" ] || die "no Linear issue $1"; echo "$id"; }
lin_describe() { lin 'mutation($i:String!,$d:String!){issueUpdate(id:$i,input:{description:$d}){success}}' --arg i "$(lin_uuid "$1")" --arg d "$body" >/dev/null; }
lin_set_group() { # id Group value
  local j lid ids; j="$(lin_issue "$1")"; [ -n "$j" ] || die "no Linear issue $1"
  lid="$(lin_label_id "$3" "$2")"; [ -n "$lid" ] || die "Linear has no label '$3' in group '$2' (bash scripts/pipeline/tracker.sh setup)"
  ids="$(printf '%s' "$j" | jq -c --arg g "$2" --arg l "$lid" '[.labels.nodes[] | select(.parent.name != $g) | .id] + [$l]')"
  lin 'mutation($i:String!,$l:[String!]!){issueUpdate(id:$i,input:{labelIds:$l}){success}}' --arg i "$(printf '%s' "$j" | jq -r .id)" --argjson l "$ids" >/dev/null
}
lin_state() {
  local name sid; name="$(state_name "$2")"
  sid="$(lin_team | jq -r --arg n "$name" '[.states.nodes[] | select(.name==$n)][0].id // empty')"
  [ -n "$sid" ] || die "the Linear team has no status '$name' (bash scripts/pipeline/tracker.sh setup)"
  lin 'mutation($i:String!,$s:String!){issueUpdate(id:$i,input:{stateId:$s}){success}}' --arg i "$(lin_uuid "$1")" --arg s "$sid" >/dev/null
}
lin_setup() {
  local t tid labels missing=() g v s name gid
  t="$(lin_team)"; [ -n "$t" ] || die "Linear has no team with key $key"; tid="$(printf '%s' "$t" | jq -r .id)"
  labels="$(lin_labels)"
  for g in Stage Owner; do
    printf '%s' "$labels" | jq -e --arg g "$g" 'any(.[]; .name==$g and .isGroup)' >/dev/null || missing+=("group|$g")
    for v in $(group_values "$g"); do
      printf '%s' "$labels" | jq -e --arg g "$g" --arg v "$v" 'any(.[]; .name==$v and .parent.name==$g)' >/dev/null || missing+=("label|$g|$v")
    done
  done
  for v in $(kinds); do printf '%s' "$labels" | jq -e --arg v "$v" 'any(.[]; .name==$v and .parent==null and (.isGroup|not))' >/dev/null || missing+=("label||$v"); done
  for s in $(states); do name="$(state_name "$s")"
    printf '%s' "$t" | jq -e --arg n "$name" 'any(.states.nodes[]; .name==$n)' >/dev/null || { printf '%s\n' "${missing[@]+"${missing[@]}"}" | grep -qxF "state|$name" || missing+=("state|$name"); }
  done
  report_missing "item" "${missing[@]+"${missing[@]}"}" || return 0
  for m in "${missing[@]}"; do
    IFS='|' read -r kind a b <<<"$m"
    case "$kind" in
      group) lin 'mutation($t:String!,$n:String!){issueLabelCreate(input:{teamId:$t,name:$n,isGroup:true}){success}}' --arg t "$tid" --arg n "$a" >/dev/null && echo "CREATED label group $a";;
      label)
        if [ -n "$a" ]; then gid="$(lin_labels | jq -r --arg g "$a" '[.[] | select(.name==$g and .isGroup)][0].id')"
          lin 'mutation($t:String!,$n:String!,$p:String!){issueLabelCreate(input:{teamId:$t,name:$n,parentId:$p}){success}}' --arg t "$tid" --arg n "$b" --arg p "$gid" >/dev/null && echo "CREATED label $a/$b"
        else lin 'mutation($t:String!,$n:String!){issueLabelCreate(input:{teamId:$t,name:$n}){success}}' --arg t "$tid" --arg n "$b" >/dev/null && echo "CREATED label $b"; fi;;
      state)
        local ty=started; case "$a" in Done) ty=completed;; Canceled) ty=canceled;; Todo) ty=unstarted;; esac
        lin 'mutation($t:String!,$n:String!,$ty:String!){workflowStateCreate(input:{teamId:$t,name:$n,type:$ty,color:"#f2c94c"}){success}}' --arg t "$tid" --arg n "$a" --arg ty "$ty" >/dev/null && echo "CREATED status $a ($ty)";;
    esac
  done
  write_map linear
}

# ================================================================ Jira (acli + REST) ====
# Kinds are Jira labels (free text: they need no setup). Stage/Owner are single-select custom fields when the
# project's screens carry them, else labels "stage:<v>" / "owner:<v>" (setup decides and records it in tracker.map).
# States are the project's statuses, mapped in tracker.map. Children are sub-tasks of the parent.
jira_rest() { # method path [json]
  [ -n "${JIRA_API_TOKEN:-}" ] || die "no Jira API token (bash scripts/pipeline/connect.sh login)"
  [ -n "$site" ] || die "TRACKER_URL (the Jira site) is not set in pipeline.env"
  local b=(); [ -n "${3:-}" ] && b=(-H 'Content-Type: application/json' --data "$3")
  $curl_cmd -fsS -u "${JIRA_EMAIL:-}:$JIRA_API_TOKEN" -H 'Accept: application/json' -X "$1" "$site/rest/api/3/$2" ${b[@]+"${b[@]}"}
}
jcli() { $acli_cmd jira "$@"; }
adf() { jq -Rsc '{type:"doc",version:1,content:[split("\n\n")[] | select(length>0) | {type:"paragraph",content:[{type:"text",text:.}]}]}' <<<"$1"; }
adf_text() { jq -r '[.. | objects | select(.type=="text") | .text] | join("")'; }
jira_mode() { map_get jira:groups || echo labels; }   # fields | labels
jira_check() {
  jcli auth status >/dev/null 2>&1 || die "acli is not signed in to Jira (bash scripts/pipeline/connect.sh login)"
  jira_rest GET "project/$key" >/dev/null || die "Jira has no project $key at $site (or the API token cannot see it)"
  echo "tracker: Jira project $key at $site"
}
jira_view() {
  local j; j="$(jira_rest GET "issue/$(upper "$1")?fields=summary,status,labels,description,subtasks,comment,$(map_get jira:field:Stage),$(map_get jira:field:Owner)")" || die "no Jira issue $1"
  local sf of; sf="$(map_get jira:field:Stage)"; of="$(map_get jira:field:Owner)"
  printf '%s' "$j" | jq -r --arg sf "$sf" --arg of "$of" --arg site "$site" '
    def grp($p; $f): if $f != "" then (.fields[$f].value // "") else ([.fields.labels[] | select(startswith($p)) | ltrimstr($p)] | join(",")) end;
    "ID: \(.key)\nTitle: \(.fields.summary)\nState: \(.fields.status.name)\nStage: \(grp("stage:"; $sf))\nOwner: \(grp("owner:"; $of))\n" +
    "Labels: \(.fields.labels | join(", "))\nURL: \($site)/browse/\(.key)"'
  echo "--- description"; printf '%s' "$j" | jq -c '.fields.description // {}' | adf_text
  echo "--- comments (latest 10)"
  printf '%s' "$j" | jq -c '.fields.comment.comments[-10:][]?' | while IFS= read -r c; do
    printf '[%s] %s: %s\n' "$(printf '%s' "$c" | jq -r .created)" "$(printf '%s' "$c" | jq -r .author.displayName)" "$(printf '%s' "$c" | jq -c .body | adf_text)"; done
  echo "--- children"; jira_children "$1"
}
jira_children() {
  jcli workitem search --jql "parent = $(upper "$1")" --json --fields key,summary,status,labels 2>/dev/null \
    | jq -r '(.issues // .)[] | "\(.key) | \([.fields.labels[] | select(test("^(stage|owner):") | not)] | join(",")) | \(.fields.status.name) | \(.fields.summary)"' || true
}
jira_create() {
  local ty f out; ty="$(map_get jira:subtask-type)"; ty="${ty:-Subtask}"
  f="$(mktemp)"; printf '%s' "$body" > "$f"
  out="$(jcli workitem create --project "$key" --type "$ty" --parent "$(upper "$1")" --summary "$3" --description-file "$f" --label "$2" --json)"; local rc=$?
  rm -f "$f"; [ $rc -eq 0 ] || die "could not create the Jira work item"
  printf '%s' "$out" | jq -r '.key // .issue.key // empty' | grep . || printf '%s' "$out" | ticket_id_in
}
ticket_id_in() { bash "$here/ticket-id.sh"; }
jira_comment() { local f; f="$(mktemp)"; printf '%s' "$body" > "$f"; jcli workitem comment create --key "$(upper "$1")" --body-file "$f" >/dev/null; local rc=$?; rm -f "$f"; return $rc; }
jira_describe() { jira_rest PUT "issue/$(upper "$1")" "$(jq -nc --argjson d "$(adf "$body")" '{fields:{description:$d}}')" >/dev/null; }
jira_set_group() { # id Group value
  local id g; id="$(upper "$1")"; g="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  if [ "$(jira_mode)" = fields ]; then
    jira_rest PUT "issue/$id" "$(jq -nc --arg f "$(map_get "jira:field:$2")" --arg v "$3" '{fields:{($f):{value:$v}}}')" >/dev/null
  else
    local cur ops; cur="$(jira_rest GET "issue/$id?fields=labels" | jq -c '.fields.labels')"
    ops="$(printf '%s' "$cur" | jq -c --arg p "$g:" --arg k "$g:$3" '[.[] | select(startswith($p) and . != $k) | {remove:.}] + [{add:$k}]')"
    jira_rest PUT "issue/$id" "$(jq -nc --argjson o "$ops" '{update:{labels:$o}}')" >/dev/null
  fi
}
jira_state() { jcli workitem transition --key "$(upper "$1")" --status "$(state_name "$2")" --yes >/dev/null || die "Jira has no transition to '$(state_name "$2")' for $1 (tracker.map maps pipeline states to statuses)"; }
jira_setup() {
  local p pid fields missing=() g v fid ctx opts statuses s name ty cm
  p="$(jira_rest GET "project/$key")" || die "Jira has no project $key at $site"
  pid="$(printf '%s' "$p" | jq -r .id)"
  ty="$(printf '%s' "$p" | jq -r '[.issueTypes[] | select(.subtask)][0].name // "Subtask"')"
  fields="$(jira_rest GET field)"
  statuses="$(jira_rest GET "project/$key/statuses" | jq -c '[.[].statuses[].name] | unique')"
  # Stage/Owner: fields when a Stage field is on the project's create screen, else labels (no setup needed)
  cm="$(jira_rest GET "issue/createmeta/$key/issuetypes/$(printf '%s' "$p" | jq -r '[.issueTypes[] | select(.subtask|not)][0].id')" 2>/dev/null | jq -c '[(.fields // .values)[]?.name]' 2>/dev/null || echo '[]')"
  local mode=labels
  for g in Stage Owner; do
    fid="$(printf '%s' "$fields" | jq -r --arg g "$g" '[.[] | select(.custom and .name==$g)][0].id // empty')"
    if [ -z "$fid" ]; then missing+=("field|$g")
    else
      printf '%s' "$cm" | jq -e --arg g "$g" 'index($g)' >/dev/null && mode=fields
      ctx="$(jira_rest GET "field/$fid/context" | jq -r '.values[0].id // empty')"
      if [ -z "$ctx" ]; then missing+=("context|$g|$fid")
      else opts="$(jira_rest GET "field/$fid/context/$ctx/option" | jq -c '[.values[].value]')"
        for v in $(group_values "$g"); do printf '%s' "$opts" | jq -e --arg v "$v" 'index($v)' >/dev/null || missing+=("option|$g|$fid|$ctx|$v"); done
      fi
    fi
  done
  for s in $(states); do name="$(state_name "$s")"
    printf '%s' "$statuses" | jq -e --arg n "$name" 'index($n)' >/dev/null || { printf '%s\n' "${missing[@]+"${missing[@]}"}" | grep -qxF "status|$name|$s" || missing+=("status|$name|$s"); }
  done
  jira_map_extra="jira:subtask-type|$ty"
  if ! report_missing "item" "${missing[@]+"${missing[@]}"}"; then jira_map_extra="$jira_map_extra
jira:groups|$mode"; write_map jira; return 0; fi
  for m in "${missing[@]}"; do
    IFS='|' read -r kind a b c d <<<"$m"
    case "$kind" in
      field)
        fid="$(jcli field create --name "$a" --type com.atlassian.jira.plugin.system.customfieldtypes:select \
               --searcherKey com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher --json 2>/dev/null | jq -r '.id // empty')"
        [ -n "$fid" ] || fid="$(jira_rest POST field "$(jq -nc --arg n "$a" '{name:$n,type:"com.atlassian.jira.plugin.system.customfieldtypes:select",searcherKey:"com.atlassian.jira.plugin.system.customfieldtypes:multiselectsearcher",description:"ship pipeline"}')" | jq -r .id)"
        [ -n "$fid" ] || { echo "FAILED field $a (needs Jira admin)"; continue; }
        echo "CREATED field $a ($fid)"
        ctx="$(jira_rest POST "field/$fid/context" "$(jq -nc --arg p "$pid" '{name:"ship pipeline",projectIds:[$p],issueTypeIds:[]}')" | jq -r .id)"
        jira_rest POST "field/$fid/context/$ctx/option" "$(group_values "$a" | jq -Rnc '{options:[inputs | {value:., disabled:false}]}')" >/dev/null && echo "CREATED options for $a";;
      context)
        ctx="$(jira_rest POST "field/$b/context" "$(jq -nc --arg p "$pid" '{name:"ship pipeline",projectIds:[$p],issueTypeIds:[]}')" | jq -r .id)"
        jira_rest POST "field/$b/context/$ctx/option" "$(group_values "$a" | jq -Rnc '{options:[inputs | {value:., disabled:false}]}')" >/dev/null && echo "CREATED options for $a";;
      option) jira_rest POST "field/$b/context/$c/option" "$(jq -nc --arg v "$d" '{options:[{value:$v,disabled:false}]}')" >/dev/null && echo "CREATED option $a/$d";;
      status)
        local cat=IN_PROGRESS; case "$b" in open|reopened) cat=TODO;; verified|done|wontfix) cat=DONE;; esac
        if jira_rest POST statuses "$(jq -nc --arg n "$a" --arg c "$cat" --arg p "$pid" '{scope:{type:"PROJECT",project:{id:$p}},statuses:[{name:$n,statusCategory:$c,description:"ship pipeline"}]}')" >/dev/null 2>&1; then
          echo "CREATED status $a (add it to the project's workflow to use it)"
        fi
        # until a status is in the workflow, map the pipeline state to the nearest one that is
        local near; case "$cat" in TODO) near="$(printf '%s' "$statuses" | jq -r '[.[] | select(test("to ?do|open|backlog";"i"))][0] // empty')";;
          DONE) near="$(printf '%s' "$statuses" | jq -r '[.[] | select(test("done|closed|resolved";"i"))][0] // empty')";;
          *) near="$(printf '%s' "$statuses" | jq -r '[.[] | select(test("progress|review";"i"))][0] // empty')";; esac
        [ -n "$near" ] && { jira_map_extra="$jira_map_extra
state:$b|$near"; echo "MAPPED pipeline state $b -> '$near' (no '$a' status in the workflow yet)"; };;
    esac
  done
  # re-read which mode the screens allow now that the fields exist
  mode=labels; cm="$(jira_rest GET "issue/createmeta/$key/issuetypes/$(printf '%s' "$p" | jq -r '[.issueTypes[] | select(.subtask|not)][0].id')" 2>/dev/null | jq -c '[(.fields // .values)[]?.name]' 2>/dev/null || echo '[]')"
  printf '%s' "$cm" | jq -e 'index("Stage") and index("Owner")' >/dev/null && mode=fields
  jira_map_extra="$jira_map_extra
jira:groups|$mode"
  [ "$mode" = labels ] && echo "NOTE Stage/Owner are kept as labels (stage:<v>, owner:<v>) because the fields are not on the project's screens"
  write_map jira
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

# ================================================================ dispatch ====
case "$tracker" in github) pfx=gh;; gitlab) pfx=gl;; linear) pfx=lin;; jira) pfx=jira;; esac
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
    bash "$here/tracker.sh" set "$id" "stage=$st" "owner=$ow" || exit 1
    "${pfx}_comment" "$id" && echo "handoff: $id -> Stage $st, Owner $ow";;
  state)
    need_id "${1:-}"; valid_in "${2:-}" $(states) || die "state must be one of: $(states | tr '\n' ' ')"; "${pfx}_state" "$1" "$2";;
  setup) [ "${1:-}" = --check ] && check_only=1; "${pfx}_setup"; if [ "$check_only" = 1 ] && [ "$nmissing" -gt 0 ]; then exit 2; fi;;
  *) die "usage: tracker.sh <check|view|children|create|comment|describe|set|handoff|state|setup> ... (see the header)";;
esac
