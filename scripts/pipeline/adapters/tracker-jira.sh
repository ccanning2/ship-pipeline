#!/usr/bin/env bash
# The Jira tracker adapter, installed as scripts/pipeline/tracker.sh when TRACKER="jira".
# Verbs, exit codes and test doubles: scripts/pipeline/lib/tracker-common.sh. To change tracker, re-run /pipeline-init.
# adapter: tracker=jira
set -uo pipefail
tracker=jira; pfx=jira
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/tracker-common.sh"

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

tracker_main "$@"
