#!/usr/bin/env bash
# The Linear tracker adapter, installed as scripts/pipeline/tracker.sh when TRACKER="linear".
# Verbs, exit codes and test doubles: scripts/pipeline/lib/tracker-common.sh. To change tracker, re-run /pipeline-init.
# adapter: tracker=linear
set -uo pipefail
tracker=linear; pfx=lin
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/tracker-common.sh"

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

tracker_main "$@"
