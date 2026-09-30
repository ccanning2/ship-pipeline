#!/usr/bin/env bash
# The GitLab issues tracker adapter, installed as scripts/pipeline/tracker.sh when TRACKER="gitlab".
# Verbs, exit codes and test doubles: scripts/pipeline/lib/tracker-common.sh. To change tracker, re-run /pipeline-init.
# adapter: tracker=gitlab
set -uo pipefail
tracker=gitlab; pfx=gl
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/tracker-common.sh"

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

tracker_main "$@"
