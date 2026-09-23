#!/usr/bin/env bash
# The GitHub Issues tracker adapter, installed as scripts/pipeline/tracker.sh when TRACKER="github".
# Verbs, exit codes and test doubles: scripts/pipeline/lib/tracker-common.sh. To change tracker, re-run /pipeline-init.
# adapter: tracker=github
set -uo pipefail
tracker=github; pfx=gh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/tracker-common.sh"

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

tracker_main "$@"
